import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty,
      'Defina SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY com --dart-define');
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  try {
    await setupJobNotifications();
  } catch (_) {
    // notificação é um extra: o app funciona sem ela
  }
  runApp(const ProviderScope(child: RecrutadorApp()));
}
