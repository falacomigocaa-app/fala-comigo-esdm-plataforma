import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

/// Estado explícito do consentimento para evitar que a permissão do sistema
/// seja tratada como autorização de compartilhamento.
enum LocationConsent { unknown, denied, granted }

class LocationService {
  LocationService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _consentKey = 'location.consent.v1';
  final FlutterSecureStorage _storage;

  Future<LocationConsent> readConsent() async {
    final value = await _storage.read(key: _consentKey);
    return switch (value) {
      'granted' => LocationConsent.granted,
      'denied' => LocationConsent.denied,
      _ => LocationConsent.unknown,
    };
  }

  Future<void> grantConsent() => _storage.write(
    key: _consentKey,
    value: 'granted',
  );

  /// Revogação apaga o consentimento local. Nenhum rastreamento em segundo
  /// plano é iniciado por este serviço.
  Future<void> revokeConsent() => _storage.write(
    key: _consentKey,
    value: 'denied',
  );

  Future<Position> readCurrentPosition() async {
    if (await readConsent() != LocationConsent.granted) {
      throw const LocationException('consent_required');
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('service_disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('permission_denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('permission_denied_forever');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}

class LocationException implements Exception {
  const LocationException(this.code);

  final String code;

  String get userMessage => switch (code) {
    'consent_required' => 'Ative o consentimento antes de solicitar a posição.',
    'service_disabled' => 'Ative o GPS nas configurações do aparelho.',
    'permission_denied' => 'A permissão de localização foi recusada.',
    'permission_denied_forever' =>
      'A permissão foi bloqueada. Libere-a nas configurações do aparelho.',
    _ => 'Não foi possível obter a localização agora.',
  };

  @override
  String toString() => 'LocationException($code)';
}
