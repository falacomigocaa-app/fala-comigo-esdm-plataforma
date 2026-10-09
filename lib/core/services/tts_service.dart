import 'package:flutter_tts/flutter_tts.dart';

/// Serviço centralizado de síntese de voz (Text-to-Speech).
///
/// Configurado para português do Brasil (pt-BR), com parâmetros
/// ajustados para clareza e baixa latência (<100ms), conforme
/// recomendado para apps de CAA infantil.
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.45); // um pouco mais lento, ideal p/ crianças
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    // O alerta de transição só libera a tela depois que a mensagem foi
    // realmente reproduzida pela criança.
    await _tts.awaitSpeakCompletion(true);

    _initialized = true;
  }

  /// Fala um texto imediatamente, interrompendo qualquer fala anterior.
  Future<void> speak(String text) async {
    if (!_initialized) await init();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
