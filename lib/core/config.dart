/// App configuration. Supabase credentials are injected at build/run time via
/// `--dart-define`, so no secrets live in source control.
///
/// Run/build like:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// (The repo ships a `run.sh` / `.env` helper — see trio/README.md.)
class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True when both credentials are present so the app can talk to Supabase.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const String appName = 'Trio';
}
