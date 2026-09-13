import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'vault.dart';
import 'package:local_auth/local_auth.dart';
import 'custom_snackbar.dart';
// PHASE14C: the Vault LOCK (password/last-viewed) now goes through
// VaultLockRepository (FastAPI) instead of Firestore — see this file's
// _checkVaultPassword/_createVaultPassword/_authenticateVaultPassword
// below. firebase_auth/cloud_firestore stay imported above: _fetchName/
// _fetchProfileImage still read the Profile doc's name/profileImage
// fields, which belong to a not-yet-migrated feature (Profile) and are
// deliberately left untouched — see the PHASE14C implementation report.
import 'core/network/api_exception.dart';
import 'data/repositories/vault_lock_repository.dart';

class VaultPasswordPage extends StatefulWidget {
  const VaultPasswordPage({Key? key}) : super(key: key);

  @override
  State<VaultPasswordPage> createState() => _VaultPasswordPageState();
}

class _VaultPasswordPageState extends State<VaultPasswordPage> {
  bool _obscureText = true;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();
  String? name;
  String? profileImageUrl;
  bool isLoading = true;
  bool isCreating = false; // true if creating password, false if authenticating
  String? errorText;
  final LocalAuthentication auth = LocalAuthentication();

  /// True while a create/unlock request is in flight — disables the
  /// Create/Unlock Now button and swaps its label for a spinner, so a
  /// slow/duplicate tap can't fire a second overlapping request
  /// (PHASE14C — same pattern as `shoutout_page.dart`'s `_loading`/
  /// `scheduler_details_page.dart`'s `_isSaving`). Deliberately a new,
  /// separate flag from [isLoading]: that one still gates the page's
  /// initial full-card load exactly as before this migration.
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchName();
    _fetchProfileImage();
    _checkVaultPassword();
  }

  Future<void> _fetchName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      final username = user!.email!.split('@')[0];
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(username)
          .get();
      setState(() {
        name = doc.data()?['name'] ?? username;
      });
    } else {
      setState(() {
        name = 'User';
      });
    }
  }

  Future<void> _fetchProfileImage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email != null) {
        final username = user!.email!.split('@')[0];
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(username)
            .get();
        
        if (doc.exists && doc.data() != null) {
          setState(() {
            profileImageUrl = doc.data()!['profileImage'];
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  /// Loads this user's Vault-lock state via `GET /vault/lock` (PHASE14C —
  /// replacing the old Firestore `vaultPasswordHash` read). `configured:
  /// false` (never a 404) means no backend Vault password has been
  /// created yet — including for a user who already has an old,
  /// unmigrated Firestore Vault password; per PHASE14C Step 7/8, that old
  /// password is never read, compared against, or migrated. This is
  /// treated exactly like a brand-new Vault setup: [isCreating] is set to
  /// `true`, showing the Create form.
  Future<void> _checkVaultPassword() async {
    try {
      final state = await VaultLockRepository.instance.getState();
      if (!mounted) return;
      setState(() {
        isCreating = !state.configured;
        isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { isLoading = false; });
      showCustomSnackBar(context, _friendlyVaultLockError(e), icon: Icons.error_outline);
    }
  }

  /// Maps a Vault-lock [ApiException] to a short, clean, user-facing
  /// message — same approach as `journal_page.dart`'s
  /// `_friendlyJournalError`. Used as-is for [_checkVaultPassword]/
  /// [_createVaultPassword] (where a 401 genuinely means "your session
  /// expired" — creating a lock has no "wrong password" concept).
  /// [_authenticateVaultPassword] special-cases 401 itself instead of
  /// calling this, because for `/vault/unlock` specifically a 401 means
  /// "incorrect Vault password" (see that method's own doc).
  String _friendlyVaultLockError(ApiException e) {
    if (e is ConflictException) {
      return 'A Vault password already exists for your account.';
    }
    if (e is ValidationException) {
      return "That password couldn't be saved — please check it and try again.";
    }
    if (e is NetworkException) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (e is UnauthorizedException) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong with your Vault password. Please try again.';
  }

  /// Creates this user's Vault password via `POST /vault/lock` (PHASE14C
  /// — replacing the old Firestore `.set()` + local SHA-256 hashing).
  /// Existing client-side validation (non-empty, matching, minimum 6
  /// characters) is unchanged; the backend itself Argon2-hashes the
  /// password and never returns it or its hash (PHASE14B backend contract
  /// report, Section 6/11) — nothing here ever computes or stores a hash
  /// on-device.
  ///
  /// The UI is only updated (switching to the Unlock form) once the
  /// backend confirms creation — never optimistically. On failure, the
  /// user stays on this form with a clear, friendly error; a failed
  /// creation is never treated as success.
  Future<void> _createVaultPassword() async {
    setState(() { errorText = null; });
    final pass = _passwordController.text.trim();
    final rePass = _rePasswordController.text.trim();
    if (pass.isEmpty || rePass.isEmpty) {
      setState(() { errorText = 'Please fill both fields.'; });
      return;
    }
    if (pass.length < 6) {
      setState(() { errorText = 'Password must be at least 6 characters.'; });
      return;
    }
    if (pass != rePass) {
      setState(() { errorText = 'Passwords do not match.'; });
      return;
    }
    setState(() { _isSubmitting = true; });
    try {
      await VaultLockRepository.instance.createLock(pass);
      if (!mounted) return;
      setState(() {
        isCreating = false;
        _isSubmitting = false;
        errorText = null;
        _passwordController.clear();
        _rePasswordController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault password created!')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; });
      showCustomSnackBar(context, _friendlyVaultLockError(e), icon: Icons.error_outline);
    }
  }

  /// Verifies this user's Vault password via `POST /vault/unlock`
  /// (PHASE14C — replacing the old local SHA-256 comparison against a
  /// Firestore-stored hash). The backend performs the Argon2 comparison
  /// and, on success, advances `last_viewed_at`/`previous_viewed_at`
  /// itself — this method never writes those anywhere (no separate
  /// Firestore or backend "record a view" call).
  ///
  /// On a 401, this is shown as the existing "Incorrect password." inline
  /// error (unchanged wording) rather than the app's usual "session
  /// expired" message: `POST /vault/unlock` deliberately returns the
  /// exact same 401 both when the password is wrong AND when no Vault
  /// lock has been created yet at all, so a caller can never tell those
  /// two apart (PHASE14B backend contract report, Section 5/7) — showing
  /// "Incorrect password." is the correct, safe reading of that 401 here,
  /// per PHASE14C Step 6 ("do not reveal whether the backend lock exists
  /// beyond the API contract"). Note `ApiClient` itself will have already
  /// attempted one token-refresh-and-retry before this 401 ever reaches
  /// here (its interceptor treats every 401 as a possible expired
  /// session) — harmless, since the retry also fails with the same 401
  /// (the password is still wrong), it's just an extra round trip.
  ///
  /// Vault only opens once the backend has confirmed the password is
  /// correct — never on a network/server error, and never optimistically.
  Future<void> _authenticateVaultPassword() async {
    setState(() { errorText = null; });
    final pass = _passwordController.text.trim();
    if (pass.isEmpty) {
      setState(() { errorText = 'Please enter your password.'; });
      return;
    }
    setState(() { _isSubmitting = true; });
    try {
      await VaultLockRepository.instance.unlock(pass);
      if (!mounted) return;
      setState(() { _isSubmitting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault unlocked!')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => VaultPage()),
      );
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        errorText = 'Incorrect password.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; });
      showCustomSnackBar(context, _friendlyVaultLockError(e), icon: Icons.error_outline);
    }
  }

  /// Device-local biometric unlock (unchanged mechanism — `local_auth`).
  ///
  /// PHASE14C: this has NEVER been checked against the stored Vault
  /// password — not the old Firestore hash, and not the new backend one
  /// either. A successful device biometric prompt alone has always
  /// admitted the user here, independent of the real password check;
  /// preserving that now is not a new or weakened claim, it is exactly
  /// the trust level this screen already had before this migration. What
  /// DOES change: the old Firestore `vaultLastViewed`/
  /// `vaultPrevLastViewed` write on success is removed — Vault-lock
  /// persistence no longer touches Firestore at all — and nothing
  /// replaces it, because there is no `POST /vault/unlock/biometric` (see
  /// PHASE14B backend contract report and PHASE14C Step 10: inventing one
  /// now would mean guessing at an unreviewed security protocol). A
  /// biometric-only unlock therefore does NOT call the backend and does
  /// NOT advance `last_viewed_at`/`previous_viewed_at` — those now only
  /// ever change via a real `POST /vault/unlock` with the correct
  /// password. This is a known, documented limitation of this phase; full
  /// biometric/backend synchronization (e.g. a server-verifiable
  /// biometric protocol) is deferred to a future phase.
  Future<void> _authenticateWithBiometrics() async {
    try {
      bool isSupported = await auth.isDeviceSupported();
      bool canCheckBiometrics = await auth.canCheckBiometrics;
      if (!isSupported) {
        showCustomSnackBar(
          context,
          'Biometric hardware not available on this device.',
          icon: Icons.error_outline,
        );
        return;
      }
      if (!canCheckBiometrics) {
        showCustomSnackBar(
          context,
          'No biometrics enrolled. Please set up fingerprint/face unlock in your device settings.',
          icon: Icons.info_outline,
        );
        return;
      }
      bool isAuthenticated = await auth.authenticate(
        localizedReason: 'Unlock your vault with biometrics',
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      if (isAuthenticated) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => VaultPage()),
        );
      } else {
        showCustomSnackBar(
          context,
          'Biometric authentication failed',
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        'Biometric authentication error: $e',
        icon: Icons.error_outline,
      );
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D4),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Center(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title and subtitle
                          Row(
                            children: [
                              const Text(
                                'Vault',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDCBB0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Treasures of your heart,\nprotected here 💖',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          // Card
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              children: [
                                // Panda user icon in a circle (centered at the top)
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1A1A1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: ClipOval(
                                      child: profileImageUrl != null && profileImageUrl!.isNotEmpty
                                          ? Image.network(
                                              profileImageUrl!,
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Image.asset(
                                                  'assets/panda.png',
                                                  width: 56,
                                                  height: 56,
                                                  fit: BoxFit.cover,
                                                );
                                              },
                                            )
                                          : Image.asset(
                                              'assets/panda.png',
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Welcome text with Firestore name
                                Text.rich(
                                  TextSpan(
                                    text: 'Welcome Back ',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.black,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: name ?? 'User',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const TextSpan(text: ','),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (isCreating) ...[
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Enter Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _rePasswordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Re Enter Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting ? null : _createVaultPassword,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFDA8D7A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(32),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                            )
                                          : const Text(
                                              'Create',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                ] else ...[
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: _obscureText,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFFFE0F0),
                                      hintText: 'Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: Color(0xFFB39DDB),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscureText
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureText = !_obscureText;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting ? null : _authenticateVaultPassword,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE19378),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(32),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                            )
                                          : const Text(
                                              'Unlock Now',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                                if (errorText != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    errorText!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ],
                                // Privacy note
                                Row(
                                  children: [
                                    Transform.translate(
                                      offset: Offset(6, -8),
                                      child: Icon(
                                        Icons.lock,
                                        size: 20,
                                        color: Color(0xFFB0AEB1),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Your information is private and protected.\nYour secrets are safe here. We\'ve got your back',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7B7B7B),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                // Fingerprint icon
                                IconButton(
                                  icon: Icon(Icons.fingerprint, size: 40),
                                  onPressed: _authenticateWithBiometrics,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      // Removed bottomNavigationBar
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool selected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 32,
          color: selected ? const Color(0xFFDA8D7A) : Colors.grey,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFDA8D7A) : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
