import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/services/supabase_session_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  MediaKit.ensureInitialized();
  final projectUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
  final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
  final supabaseConfigured = projectUrl.isNotEmpty && anonKey.isNotEmpty;
  if (supabaseConfigured) {
    await Supabase.initialize(
      url: projectUrl,
      publishableKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SupabaseSessionStorage(),
      ),
    );
  }
  runApp(SecureVaultApp(supabaseConfigured: supabaseConfigured));
}
