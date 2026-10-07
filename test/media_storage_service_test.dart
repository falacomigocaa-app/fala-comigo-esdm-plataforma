import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fala_comigo/core/services/media_storage_service_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final secureValues = <String, String>{};
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('fala_comigo_media_test_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      switch (call.method) {
        case 'write':
          secureValues[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureValues[args['key'] as String];
        case 'delete':
          secureValues.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureValues.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
          return '${root.path}/documents';
        case 'getTemporaryDirectory':
          return '${root.path}/temporary';
        default:
          throw MissingPluginException('Método não simulado: ${call.method}');
      }
    });
  });

  tearDownAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    await root.delete(recursive: true);
  });

  test('rejeita origem de mídia inexistente', () async {
    expect(
      () => MediaStorageService.persistFile(
        '/tmp/fala_comigo_missing_source_9f4c.jpg',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('materialização de caminho ausente falha sem produzir arquivo',
      () async {
    expect(
      () => MediaStorageService.materializeForReading(
        '/tmp/fala_comigo_missing_media_9f4c.jpg.fcm',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('imagem pode ser lida em memória sem materializar arquivo plaintext',
      () async {
    final source = File('${root.path}/memory-image.jpg');
    final contents = [1, 2, 3, 4, 5, 6];
    await source.writeAsBytes(contents);
    final encryptedPath = await MediaStorageService.persistFile(source.path);

    expect(
        await MediaStorageService.readBytesForDisplay(encryptedPath), contents);
    expect(
      await Directory('${root.path}/temporary/fala_comigo_media_preview')
          .exists(),
      isFalse,
    );
  });

  test('arquivo temporário materializado pode ser liberado explicitamente',
      () async {
    final source = File('${root.path}/share-video.mp4');
    final contents = [7, 8, 9, 10];
    await source.writeAsBytes(contents);
    final encryptedPath = await MediaStorageService.persistFile(source.path);
    final preview =
        await MediaStorageService.materializeForReading(encryptedPath);

    expect(await preview.readAsBytes(), contents);
    expect(await preview.exists(), isTrue);
    await MediaStorageService.releaseMaterializedFile(preview);
    expect(await preview.exists(), isFalse);
  });

  test('gravação temporária usa diretório privado e pode ser removida', () async {
    final path = await MediaStorageService.createTemporaryRecordingPath('alert-1');
    final recording = File(path);
    await recording.writeAsBytes([8, 9, 10]);

    expect(await recording.exists(), isTrue);
    await MediaStorageService.deleteTemporaryRecording(path);
    expect(await recording.exists(), isFalse);
  });

  test(
      'limpeza no bootstrap remove previews órfãos sem apagar mídia permanente',
      () async {
    final temporaryRoot = Directory('${root.path}/temporary');
    final previews =
        Directory('${temporaryRoot.path}/fala_comigo_media_preview');
    final recordings =
        Directory('${temporaryRoot.path}/fala_comigo_audio_recordings');
    final permanent = Directory('${root.path}/documents/fala_comigo_media');
    await previews.create(recursive: true);
    await recordings.create(recursive: true);
    await permanent.create(recursive: true);
    await File('${previews.path}/orphan.jpg').writeAsBytes([1]);
    await File('${recordings.path}/interrupted.m4a').writeAsBytes([2]);
    final preservedFile = File('${permanent.path}/encrypted.fcm');
    await preservedFile.writeAsBytes([3]);

    await MediaStorageService.clearStalePreviews();

    expect(await previews.exists(), isFalse);
    expect(await recordings.exists(), isFalse);
    expect(await preservedFile.exists(), isTrue);
  });
}
