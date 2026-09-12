/// Mirrors `app.schemas.auth.TokenResponse` — the body returned by
/// `POST /auth/register`, `POST /auth/login`, and `POST /auth/refresh`.
class TokenResponseModel {
  const TokenResponseModel({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  /// Access-token lifetime in seconds (900 = 15 minutes with the backend's
  /// default `ACCESS_TOKEN_EXPIRE_MINUTES` — verified directly against a
  /// live response, see PHASE7_API_INTEGRATION.md).
  final int expiresIn;

  factory TokenResponseModel.fromJson(Map<String, dynamic> json) {
    return TokenResponseModel(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }
}
