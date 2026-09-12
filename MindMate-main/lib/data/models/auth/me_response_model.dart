import 'profile_model.dart';
import 'user_model.dart';

/// Mirrors `app.schemas.auth.MeResponse` — the body of `GET /auth/me`.
class MeResponseModel {
  const MeResponseModel({required this.user, required this.profile});

  final UserModel user;
  final ProfileModel profile;

  factory MeResponseModel.fromJson(Map<String, dynamic> json) {
    return MeResponseModel(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      profile: ProfileModel.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }
}
