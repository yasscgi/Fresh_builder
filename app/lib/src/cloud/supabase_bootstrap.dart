import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class FreshSupabaseBootstrap {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bmniofzylmjfvibxpyzx.supabase.co',
  );

  static const publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool _initialized = false;

  static bool get isConfigured => publishableKey.trim().isNotEmpty;
  static bool get isInitialized => _initialized;

  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!isConfigured) return false;

    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    _initialized = true;
    return true;
  }

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;

  static SupabaseClient requireClient() {
    final value = client;
    if (value == null) {
      throw StateError(
        'Supabase is not initialized. Pass SUPABASE_PUBLISHABLE_KEY with --dart-define.',
      );
    }
    return value;
  }
}
