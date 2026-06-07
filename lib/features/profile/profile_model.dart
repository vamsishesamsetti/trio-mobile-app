/// The signed-in user's profile row (public.profiles).
class Profile {
  final String id;
  final String? displayName;
  final String? email;
  final String? avatarUrl;
  final String defaultCurrency;

  const Profile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.defaultCurrency,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        displayName: m['display_name'] as String?,
        email: m['email'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        defaultCurrency: (m['default_currency'] as String?) ?? 'USD',
      );
}
