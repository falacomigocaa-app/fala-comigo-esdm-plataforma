import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../../features/transition_alerts/domain/models/transition_alert.dart';
import 'media_storage_service.dart';
import 'tts_service.dart';

/// Reproduz a mensagem do alerta no instante em que a tela de transição abre.
///
/// A ordem é: gravação privada do familiar, TTS configurado e, por último,
/// o sinal de alerta do sistema operacional. O fallback garante feedback
/// audível mesmo quando a mídia foi removida ou o TTS não está disponível.
class TransitionAlertAudioService {
  TransitionAlertAudioService._();

  static final TransitionAlertAudioService instance =
      TransitionAlertAudioService._();

  final AudioPlayer _player = AudioPlayer();

  Future<void> play(TransitionAlert alert) async {
    // O bip é obrigatório: não depende do tipo de mensagem nem de um áudio
    // gravado que possa ter sido removido do aparelho.
    await _playAlarmTone();

    if (alert.audioType == 'gravado' && alert.recordedAudioPath != null) {
      final played = await _playRecorded(alert.recordedAudioPath!);
      if (played) return;
    }

    final text = alert.effectiveMessageText;
    if (text.isNotEmpty) {
      try {
        await TtsService.instance.speak(text);
        return;
      } catch (_) {
        // Continua para o sinal do sistema quando o TTS falhar.
      }
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Algumas plataformas não expõem o canal de som do sistema.
    }
  }

  Future<void> _playAlarmTone() async {
    try {
      await _player.stop();
      final completed = _player.onPlayerComplete.first;
      await _player.play(
        AssetSource('sounds/transition_alarm.wav'),
        volume: 1.0,
      );
      await completed;
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        // A mensagem ainda será tentada em seguida.
      }
    }
  }

  Future<bool> _playRecorded(String path) async {
    dynamic preview;
    try {
      preview = await MediaStorageService.materializeForReading(path);
      if (!await preview.exists()) return false;

      await _player.stop();
      final completed = _player.onPlayerComplete.first;
      await _player.play(DeviceFileSource(preview.path));
      await completed;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (preview != null) {
        try {
          await MediaStorageService.releaseMaterializedFile(preview);
        } catch (_) {
          // A limpeza não pode impedir o fallback de áudio.
        }
      }
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
