/// Mirrors `app.schemas.user.UserRead` exactly — field names and types
/// verified directly against a live backend response (see
/// PHASE7_API_INTEGRATION.md). Nothing here is guessed: `id` is the
/// backend's UUID, not the old app's `email.split('@')[0]` username (see
/// PHASE6_INTEGRATION_AUDIT.md, Step 7/11) — this is the one identifier the
/// rest of the FastAPI-backed app should ever treat as "the user's ID"
/// going forward.
class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.isActive,
    required this.isVerified,
    required this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final bool isActive;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      isActive: json['is_active'] as bool,
      isVerified: json['is_verified'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] == null ? null : DateTime.parse(json['last_login_at'] as String),
    );
  }
}
