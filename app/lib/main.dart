import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

// Configuração via --dart-define (nunca coloque chaves no código).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      'Defina SUPABASE_URL e SUPABASE_ANON_KEY com --dart-define');
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const ProviderScope(child: RecrutadorApp()));
}
