/// Mirrors `app.schemas.profile.ProfileRead`. Every field is nullable
/// because the backend populates them incrementally after registration
/// (see PHASE6_INTEGRATION_AUDIT.md, Step 10/Appendix — there is currently
/// no `PATCH` endpoint for these, so today they only ever come back null;
/// this model still reflects the real, complete response shape so it
/// doesn't need to change the day that gap is closed).
class ProfileModel {
  const ProfileModel({
    this.fullName,
    this.ageGroup,
    this.phone,
    this.city,
    this.country,
    this.profileImageUrl,
    this.onboardingCompletedAt,
  });

  final String? fullName;
  final String? ageGroup;
  final String? phone;
  final String? city;
  final String? country;
  final String? profileImageUrl;
  final DateTime? onboardingCompletedAt;

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      fullName: json['full_name'] as String?,
      ageGroup: json['age_group'] as String?,
      phone: json['phone'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      onboardingCompletedAt: json['onboarding_completed_at'] == null
          ? null
          : DateTime.parse(json['onboarding_completed_at'] as String),
    );
  }
}
