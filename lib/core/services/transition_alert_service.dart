import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/transition_alerts/domain/models/transition_alert.dart';

/// Identificador do canal de notificação do Alerta de Transição de
/// Atividade — precisa de alta prioridade e "tela cheia" para
/// acordar o aparelho e chamar a atenção, do mesmo jeito que um
/// despertador ou uma ligação.
// v2 força a recriação do canal com som de alarme em instalações antigas
// que possam ter criado o canal anterior sem áudio.
const String _channelId = 'transition_alert_channel_v2';
const String _channelName = 'Alertas de Transição';
const String _channelDescription =
    'Avisos de transição de atividade com contagem visual e checklist';
const String _parentReminderChannelId = 'parent_reminder_channel';
const String _parentReminderChannelName = 'Lembretes do Responsável';
const String _parentReminderChannelDescription =
    'Lembretes locais para consultar a rotina do Fala Comigo';

/// Prefixo do payload usado para identificar, quando a notificação é
/// tocada, qual TransitionAlert deve abrir a tela em tela cheia.
const String transitionAlertPayloadPrefix = 'transition_alert:';

/// Serviço responsável por dois papéis do Alerta de Transição de
/// Atividade: pedir as permissões do Android e disparar/agendar as
/// notificações em tela cheia.
class TransitionAlertService {
  TransitionAlertService._();
  static final TransitionAlertService instance = TransitionAlertService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Chamado quando o usuário toca numa notificação (ou ela dispara
  /// em tela cheia com o app já aberto). Recebe o ID do
  /// TransitionAlert correspondente. Definido pelo app na Fase D,
  /// quando a tela de alerta existir.
  void Function(String alertId)? onAlertTriggered;
  String? _pendingAlertId;

  void setAlertHandler(void Function(String alertId) handler) {
    onAlertTriggered = handler;
    final pending = _pendingAlertId;
    _pendingAlertId = null;
    if (pending != null) handler(pending);
  }

  Future<void> init() async {
    // Fuso horário fixo em horário de Brasília, para simplificar
    // (o app é voltado ao público brasileiro).
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    // Caso o app tenha sido aberto justamente por causa de um alerta
    // (estava fechado quando o alerta disparou).
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _handlePayload(launchDetails?.notificationResponse?.payload);
    }
  }

  /// Remove notificações exibidas e agendadas antes de apagar os dados locais.
  /// Flutter Web não tem implementação deste plugin.
  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  void _handlePayload(String? payload) {
    if (payload == null || !payload.startsWith(transitionAlertPayloadPrefix)) {
      return;
    }
    final alertId = payload.substring(transitionAlertPayloadPrefix.length);
    final handler = onAlertTriggered;
    if (handler == null) {
      _pendingAlertId = alertId;
    } else {
      handler(alertId);
    }
  }

  /// Pede as permissões necessárias no Android: notificações, alarme
  /// exato e tela cheia. Deve ser chamado a partir de uma tela (ex:
  /// ao criar o primeiro alerta), nunca silenciosamente ao abrir o
  /// app, para o responsável entender o motivo do pedido.
  Future<void> requestPermissions() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
      await androidPlugin.requestFullScreenIntentPermission();
    }
    final darwinPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await darwinPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Verifica o status real das permissões no Android, para
  /// diagnóstico visível na tela (em vez de falhas silenciosas).
  Future<String> checkPermissionStatus() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      return 'Não foi possível verificar nesta plataforma.';
    }
    final notificationsEnabled = await androidPlugin.areNotificationsEnabled();
    final exactAlarmsAllowed =
        await androidPlugin.canScheduleExactNotifications();
    return 'Notificações: ${notificationsEnabled == true ? "OK" : "BLOQUEADAS"} | '
        'Alarme exato: ${exactAlarmsAllowed == true ? "OK" : "BLOQUEADO"}';
  }

  NotificationDetails _buildDetails(TransitionAlert alert) {
    final vibrationPattern = alert.vibrationPattern.isEmpty
        ? null
        : Int64List.fromList(alert.vibrationPattern);
    final channelId = '${_channelId}_${alert.notificationId}';
    final volume = alert.soundVolume.clamp(0.0, 1.0).toDouble();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.private,
        sound: const RawResourceAndroidNotificationSound('transition_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        playSound: true,
        ongoing: true,
        autoCancel: false,
        enableVibration: vibrationPattern != null,
        vibrationPattern: vibrationPattern,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        criticalSoundVolume: alert.hasSound ? volume : null,
      ),
    );
  }

  NotificationDetails _buildParentReminderDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _parentReminderChannelId,
        _parentReminderChannelName,
        channelDescription: _parentReminderChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        visibility: NotificationVisibility.private,
        playSound: true,
        enableVibration: false,
      ),
    );
  }

  Future<void> scheduleParentReminder({
    required int notificationId,
    required int hour,
    required int minute,
    required List<int> weekdays,
  }) async {
    await cancelParentReminder(notificationId);
    for (final weekday in weekdays) {
      final scheduledDate =
          nextTransitionAlertOccurrence(weekday, hour, minute);
      await _plugin.zonedSchedule(
        notificationId + weekday,
        'Lembrete do responsável',
        'Confira a rotina do Fala Comigo.',
        scheduledDate,
        _buildParentReminderDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> cancelParentReminder(int notificationId) async {
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(notificationId + weekday);
    }
  }

  /// Dispara o alerta imediatamente (modo manual).
  Future<void> triggerNow(TransitionAlert alert) async {
    await _plugin.show(
      alert.notificationId,
      'Lembrete do Fala Comigo',
      alert.effectiveMessageText.isEmpty
          ? 'Hora de mudar de atividade!'
          : alert.effectiveMessageText,
      _buildDetails(alert),
      payload: '$transitionAlertPayloadPrefix${alert.id}',
    );
  }

  /// Adia somente a ocorrência atual, preservando o alerta recorrente.
  Future<void> snoozeForFiveMinutes(TransitionAlert alert) async {
    final snoozeId = alert.notificationId + 100000000;
    await _plugin.zonedSchedule(
      snoozeId,
      'Lembrete adiado',
      alert.effectiveMessageText.isEmpty
          ? 'Hora de mudar de atividade!'
          : alert.effectiveMessageText,
      tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
      _buildDetails(alert),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: '$transitionAlertPayloadPrefix${alert.id}',
    );
  }

  /// Agenda (ou reagenda) as notificações recorrentes do alerta, uma
  /// para cada dia da semana selecionado. Cada dia usa seu próprio ID
  /// de notificação (base + número do dia) para poder ser cancelado
  /// individualmente depois.
  Future<void> scheduleRecurring(TransitionAlert alert) async {
    if (kIsWeb) return;
    await cancelSchedule(alert);
    if (!alert.isActive ||
        (!alert.isScheduled && !alert.isRecurring) ||
        alert.effectiveScheduledHour == null ||
        alert.effectiveScheduledMinute == null ||
        alert.scheduledWeekdays.isEmpty) {
      return;
    }

    for (final weekday in alert.scheduledWeekdays) {
      final scheduledDate = nextTransitionAlertOccurrence(
        weekday,
        alert.effectiveScheduledHour!,
        alert.effectiveScheduledMinute!,
        advanceMinutes: alert.advanceTime,
      );
      await _plugin.zonedSchedule(
        alert.notificationId + weekday,
        'Lembrete do Fala Comigo',
        alert.effectiveMessageText.isEmpty
            ? 'Hora de mudar de atividade!'
            : alert.effectiveMessageText,
        scheduledDate,
        _buildDetails(alert),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: '$transitionAlertPayloadPrefix${alert.id}',
      );
    }
  }

  /// Cancela as notificações agendadas (nos 7 dias da semana) deste
  /// alerta.
  Future<void> cancelSchedule(TransitionAlert alert) async {
    if (kIsWeb) return;
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(alert.notificationId + weekday);
    }
  }
}

/// Calcula a próxima hora de disparo, já descontando a antecedência.
/// A convenção pública do app é 1=domingo ... 7=sábado.
tz.TZDateTime nextTransitionAlertOccurrence(
  int weekday,
  int hour,
  int minute, {
  int advanceMinutes = 0,
  tz.TZDateTime? nowOverride,
}) {
  final dartWeekday = weekday == 1 ? DateTime.sunday : weekday - 1;
  final now = nowOverride ?? tz.TZDateTime.now(tz.local);
  var activity = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  while (activity.weekday != dartWeekday) {
    activity = activity.add(const Duration(days: 1));
  }

  var notification = activity.subtract(Duration(minutes: advanceMinutes));
  while (!notification.isAfter(now)) {
    activity = activity.add(const Duration(days: 7));
    notification = activity.subtract(Duration(minutes: advanceMinutes));
  }
  return notification;
}
