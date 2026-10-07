/// Representa um arquivo materializado no navegador.
///
/// O suporte a mídia personalizada no Web permanece bloqueado até existir uma
/// camada de armazenamento cifrado adequada para o ambiente do navegador.
class WebMediaFile {
  final String path;

  const WebMediaFile(this.path);

  Future<bool> exists() async => false;
}

class MediaStorageService {
  MediaStorageService._();

  static Future<String> persistFile(
    String sourcePath, {
    String? extensionHint,
  }) async {
    throw UnsupportedError(
      'Mídias personalizadas exigem armazenamento local cifrado e ainda não '
      'estão disponíveis na versão Web.',
    );
  }

  static Future<WebMediaFile> materializeForReading(String path) async {
    throw UnsupportedError(
      'A leitura de mídia privada ainda não está disponível na versão Web.',
    );
  }

  static Future<void> releaseMaterializedFile(WebMediaFile file) async {}

  static Future<void> clearStalePreviews() async {}

  static Future<String> createTemporaryRecordingPath(String recordingId) async {
    throw UnsupportedError(
      'A gravação de áudio privada ainda não está disponível na versão Web.',
    );
  }

  static Future<void> deleteTemporaryRecording(String path) async {}

  static Future<void> deleteFile(String path) async {}

  static Future<void> clearAllMedia() async {}

  static Future<void> deleteEncryptionKey() async {}
}
