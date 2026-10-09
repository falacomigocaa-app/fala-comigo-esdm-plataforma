import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/transition_alert_audio_service.dart';
import '../../../../core/services/transition_alert_service.dart';
import '../../../../core/theme/hyperfocus_theme.dart';
import '../../domain/models/transition_alert.dart';
import 'transition_checklist_screen.dart';

/// Tela de alerta em tela cheia: abre ao tocar na notificação (ou
/// automaticamente, se o celular estiver desbloqueado). Toca a
/// mensagem de áudio, mostra uma contagem visual, e termina com um
/// botão grande levando ao checklist gamificado.
class TransitionAlertFullScreen extends ConsumerStatefulWidget {
  final TransitionAlert alert;

  const TransitionAlertFullScreen({super.key, required this.alert});

  @override
  ConsumerState<TransitionAlertFullScreen> createState() =>
      _TransitionAlertFullScreenState();
}

class _TransitionAlertFullScreenState
    extends ConsumerState<TransitionAlertFullScreen> {
  late int _remainingSeconds;
  Timer? _timer;
  bool _audioComplete = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.alert.countdownSeconds;
    _playAudio();
  }

  Future<void> _playAudio() async {
    await TransitionAlertAudioService.instance.play(widget.alert);
    if (!mounted) return;
    setState(() => _audioComplete = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) setState(() => _remainingSeconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hyperfocusTheme = ref.watch(hyperfocusThemeProvider);
    final color = hyperfocusTheme.primaryColor;
    final progress = widget.alert.countdownSeconds == 0
        ? 0.0
        : _remainingSeconds / widget.alert.countdownSeconds;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: color,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hyperfocusTheme != HyperfocusTheme.padrao)
                  Text(
                    hyperfocusTheme.emoji,
                    style: const TextStyle(fontSize: 64),
                  ),
                const SizedBox(height: 16),
                Text(
                  widget.alert.title.isEmpty
                      ? 'Hora de mudar de atividade!'
                      : widget.alert.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                      Text(
                        '$_remainingSeconds',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _audioComplete
                      ? () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => TransitionChecklistScreen(
                                  alert: widget.alert),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    minimumSize: const Size(240, 64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Text(
                      _audioComplete ? 'Vamos lá! 👉' : 'Ouça a mensagem…'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _audioComplete
                      ? () async {
                          try {
                            await TransitionAlertService.instance
                                .snoozeForFiveMinutes(widget.alert);
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Não foi possível adiar o alerta.'),
                                ),
                              );
                            }
                          }
                        }
                      : null,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Não me perturbe por 5 minutos'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
