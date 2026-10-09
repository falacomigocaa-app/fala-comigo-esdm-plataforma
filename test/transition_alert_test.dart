import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:fala_comigo/core/services/transition_alert_service.dart';
import 'package:fala_comigo/features/transition_alerts/domain/models/transition_alert.dart';

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
  });

  test('preserva áudio, contagem, checklist e agendamento ao serializar', () {
    final alert = TransitionAlert(
      id: 'alert-1',
      title: 'Hora de guardar',
      audioType: 'gravado',
      recordedAudioPath: '/private/audio.fcm',
      ttsText: 'Vamos guardar os brinquedos',
      countdownSeconds: 45,
      checklistItems: ['Guardar blocos', 'Escolher livro'],
      isScheduled: true,
      scheduledHour: 18,
      scheduledMinute: 30,
      scheduledWeekdays: [2, 4, 6],
      notificationId: 1200,
    );

    final restored = TransitionAlert.fromMap(alert.toMap());

    expect(restored.id, 'alert-1');
    expect(restored.audioType, 'gravado');
    expect(restored.recordedAudioPath, '/private/audio.fcm');
    expect(restored.countdownSeconds, 45);
    expect(restored.checklistItems, ['Guardar blocos', 'Escolher livro']);
    expect(restored.isScheduled, isTrue);
    expect(restored.scheduledHour, 18);
    expect(restored.scheduledMinute, 30);
    expect(restored.scheduledWeekdays, [2, 4, 6]);
    expect(restored.notificationId, 1200);
  });

  test('usa defaults seguros para um mapa legado incompleto', () {
    final alert = TransitionAlert.fromMap({'id': 'legacy-alert'});

    expect(alert.title, isEmpty);
    expect(alert.audioType, 'tts');
    expect(alert.countdownSeconds, 60);
    expect(alert.checklistItems, isEmpty);
    expect(alert.isScheduled, isFalse);
    expect(alert.scheduledWeekdays, isEmpty);
    expect(alert.notificationId, 0);
  });

  test('preserva o contrato completo do alerta', () {
    final createdAt = DateTime(2026, 10, 1, 8);
    final updatedAt = DateTime(2026, 10, 2, 9);
    final alert = TransitionAlert(
      id: 'complete-alert',
      title: 'Transição',
      description: 'Guardar os blocos antes do banho',
      audioType: 'tts',
      messageText: 'Vamos guardar os blocos.',
      advanceTime: 15,
      isScheduled: true,
      isRecurring: true,
      isActive: false,
      scheduledTime: DateTime(1970, 1, 1, 18, 30),
      scheduledWeekdays: [2, 4],
      hasSound: false,
      soundVolume: 0.5,
      vibrationPattern: [0, 100],
      createdAt: createdAt,
      updatedAt: updatedAt,
      notificationId: 77,
    );

    final restored = TransitionAlert.fromMap(alert.toMap());

    expect(restored.description, 'Guardar os blocos antes do banho');
    expect(restored.effectiveMessageText, 'Vamos guardar os blocos.');
    expect(restored.advanceTime, 15);
    expect(restored.isActive, isFalse);
    expect(restored.effectiveScheduledHour, 18);
    expect(restored.effectiveScheduledMinute, 30);
    expect(restored.daysOfWeek, [2, 4]);
    expect(restored.hasSound, isFalse);
    expect(restored.soundVolume, 0.5);
    expect(restored.vibrationPattern, [0, 100]);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
  });

  test('calcula antecedência antes do horário e mantém a ocorrência futura',
      () {
    final now = tz.TZDateTime(tz.local, 2026, 10, 12, 9);
    final occurrence = nextTransitionAlertOccurrence(
      2,
      10,
      30,
      advanceMinutes: 15,
      nowOverride: now,
    );

    expect(occurrence, tz.TZDateTime(tz.local, 2026, 10, 12, 10, 15));
    expect(occurrence.isAfter(now), isTrue);
  });

  test('avança uma semana quando a antecedência já ficou no passado', () {
    final now = tz.TZDateTime(tz.local, 2026, 10, 11, 0, 5);
    final occurrence = nextTransitionAlertOccurrence(
      1,
      0,
      5,
      advanceMinutes: 15,
      nowOverride: now,
    );

    expect(occurrence, tz.TZDateTime(tz.local, 2026, 10, 17, 23, 50));
  });
}
