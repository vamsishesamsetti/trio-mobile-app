import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'profile_model.dart';

class ProfileRepository {
  ProfileRepository(this._ref, this._db);
  final Ref _ref;
  final SupabaseClient _db;

  String get _uid => requireUserId(_ref);

  Future<Profile?> fetchMyProfile() async {
    final row =
        await _db.from('profiles').select().eq('id', _uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Upserts profile fields. Only provided values are changed.
  Future<void> updateProfile({
    String? displayName,
    String? defaultCurrency,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{'id': _uid};
    if (displayName != null) data['display_name'] = displayName;
    if (defaultCurrency != null) data['default_currency'] = defaultCurrency;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    await _db.from('profiles').upsert(data);
  }

  Future<void> updatePassword(String newPassword) async {
    await _db.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Uploads an avatar (reusing the public `receipts` bucket) and returns the
  /// public URL.
  Future<String> uploadAvatar(List<int> bytes, {String ext = 'jpg'}) async {
    final path = 'avatars/${_uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('receipts').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: true),
        );
    return _db.storage.from('receipts').getPublicUrl(path);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref, ref.watch(supabaseProvider));
});

class ProfileNotifier extends AsyncNotifier<Profile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<Profile?> build() => _repo.fetchMyProfile();

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.fetchMyProfile);
  }

  Future<void> save({String? displayName, String? defaultCurrency}) async {
    await _repo.updateProfile(
        displayName: displayName, defaultCurrency: defaultCurrency);
    await _reload();
  }

  Future<void> setAvatar(List<int> bytes) async {
    final url = await _repo.uploadAvatar(bytes);
    await _repo.updateProfile(avatarUrl: url);
    await _reload();
  }

  Future<void> changePassword(String newPassword) =>
      _repo.updatePassword(newPassword);
}

final myProfileProvider =
    AsyncNotifierProvider<ProfileNotifier, Profile?>(ProfileNotifier.new);

/// Currency used for display across the app — the user's saved default.
final displayCurrencyProvider = Provider<String>((ref) {
  return ref.watch(myProfileProvider).value?.defaultCurrency ?? 'USD';
});
