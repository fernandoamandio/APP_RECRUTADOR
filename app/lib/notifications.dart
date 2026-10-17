import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'config.dart';

/// Avisa no celular quando o worker encontra vagas novas.
///
/// O worker roda no GitHub quando o usuário toca em "Buscar vagas". Uma tarefa em segundo plano do Android (WorkManager)
/// confere o banco a cada ~2 horas e mostra uma notificação local se houver vagas novas
/// desde a última conferência. Não usa Firebase: nada a configurar fora do app.
const _taskName = 'checar-vagas-novas';
const _lastCheckKey = 'ultima_checagem_vagas';
const _channelId = 'vagas_novas';

final _plugin = FlutterLocalNotificationsPlugin();

Future<void> _initPlugin() => _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

/// Chamado no início do app: prepara as notificações e agenda a conferência periódica.
Future<void> setupJobNotifications() async {
  await _initPlugin();
  final prefs = await SharedPreferences.getInstance();
  // Primeira vez: começa a contar a partir de agora (não avisa vagas antigas)
  if (prefs.getString(_lastCheckKey) == null) {
    await prefs.setString(_lastCheckKey, DateTime.now().toUtc().toIso8601String());
  }
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(hours: 2),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Depois de pedir uma busca: confere daqui a ~15 minutos, quando o worker já deve ter terminado,
/// em vez de esperar a conferência periódica de 2 horas.
Future<void> scheduleCheckAfterSearch() => Workmanager().registerOneOffTask(
      'checar-apos-busca',
      _taskName,
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

/// Android 13+ exige pedir permissão para notificar. Chamado quando o feed abre.
Future<void> requestNotificationPermission() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await checkNewJobs();
    } catch (_) {
      // sem rede ou sessão expirada: tenta de novo na próxima janela
    }
    return true;
  });
}

Future<void> checkNewJobs() async {
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  } catch (_) {
    // já inicializado neste processo
  }
  final sb = Supabase.instance.client;
  final user = sb.auth.currentUser;
  if (user == null) return;

  final prefs = await SharedPreferences.getInstance();
  final since = prefs.getString(_lastCheckKey) ??
      DateTime.now().toUtc().subtract(const Duration(hours: 12)).toIso8601String();
  final now = DateTime.now().toUtc().toIso8601String();

  final rows = await sb
      .from('job_matches')
      .select('match_pct, jobs!inner(title, company)')
      .eq('user_id', user.id)
      .eq('status', 'new')
      .gt('created_at', since)
      .order('match_pct', ascending: false, nullsFirst: false)
      .limit(50);
  await prefs.setString(_lastCheckKey, now);
  if (rows.isEmpty) return;

  final best = rows.first;
  final job = best['jobs'] as Map<String, dynamic>;
  final pct = best['match_pct'] as int?;
  final n = rows.length;
  await _initPlugin();
  await _plugin.show(
    id: 1,
    title: n == 1 ? '1 vaga nova para você' : '$n vagas novas para você',
    body: 'Destaque: ${job['title']} · ${job['company']}${pct != null ? ' ($pct% de match)' : ''}',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(_channelId, 'Vagas novas',
          channelDescription: 'Aviso quando a busca encontra vagas novas', importance: Importance.high),
    ),
  );
}
