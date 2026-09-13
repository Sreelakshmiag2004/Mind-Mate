/// Mirrors `app.schemas.vault.VaultLockRead` — the one response shape
/// returned by every `/vault/lock`/`/vault/unlock` endpoint (PHASE14B/C).
///
/// Deliberately has NO `passwordHash`/`password` field: the backend never
/// returns one (see PHASE14B backend contract report, Section 6/11), and
/// this model has nowhere to put it even if it did — the Vault password
/// itself is never stored on-device, only sent once per attempt over the
/// authenticated API call that needs it (PHASE14C: "The Flutter app must
/// NOT ... store a password hash in Hive/SharedPreferences").
///
/// No code generation is used, matching every other model under
/// `lib/data/models` (see `journal_model.dart`, `shoutout_model.dart`).
class VaultLockModel {
  const VaultLockModel({
    required this.configured,
    this.lastViewedAt,
    this.previousViewedAt,
  });

  /// `false` means no Vault password has been created yet for this user —
  /// a normal state, not an error (PHASE14B: `GET /vault/lock` is always
  /// 200, never 404 for this case).
  final bool configured;

  /// `null` until the first successful `POST /vault/unlock`.
  final DateTime? lastViewedAt;

  /// The value [lastViewedAt] held immediately before the most recent
  /// successful unlock; `null` until there have been at least two.
  final DateTime? previousViewedAt;

  factory VaultLockModel.fromJson(Map<String, dynamic> json) {
    return VaultLockModel(
      configured: json['configured'] as bool,
      lastViewedAt: json['last_viewed_at'] == null ? null : DateTime.parse(json['last_viewed_at'] as String),
      previousViewedAt: json['previous_viewed_at'] == null
          ? null
          : DateTime.parse(json['previous_viewed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'configured': configured,
    'last_viewed_at': lastViewedAt?.toIso8601String(),
    'previous_viewed_at': previousViewedAt?.toIso8601String(),
  };
}
