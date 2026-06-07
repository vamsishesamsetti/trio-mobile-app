import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The shared Supabase client (initialized in main.dart before runApp).
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Auth state as a stream — drives the router's redirect logic.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// The currently signed-in user (or null). Recomputed when auth changes.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Convenience: the signed-in user's id, throwing if absent (used by
/// repositories that must only run while authenticated).
String requireUserId(Ref ref) {
  final id = ref.read(supabaseProvider).auth.currentUser?.id;
  if (id == null) {
    throw StateError('No authenticated user');
  }
  return id;
}
