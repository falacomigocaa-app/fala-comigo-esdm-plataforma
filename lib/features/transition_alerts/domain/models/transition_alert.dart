/// Representa um alerta local de transição de atividade.
///
/// O modelo mantém os nomes antigos (`isScheduled`, `scheduledWeekdays` e
/// `ttsText`) para ler dados já gravados, mas também expõe o contrato atual
/// usado pela área parental e pela sincronização futura.
class TransitionAlert {
  final String id;
  String title;
  String description;
  String audioType; // 'gravado' ou 'tts'
  String? recordedAudioPath;
  String? ttsText;
  String? messageText;
  String? audioUrl;
  int countdownSeconds;
  int advanceTime;
  List<String> checklistItems;
  bool isScheduled;
  bool isRecurring;
  bool isActive;
  int? scheduledHour;
  int? scheduledMinute;
  DateTime? scheduledTime;
  List<int> scheduledWeekdays; // 1 (domingo) a 7 (sábado)
  bool hasSound;
  double soundVolume;
  List<int> vibrationPattern;
  final DateTime createdAt;
  DateTime updatedAt;
  int notificationId;
  String syncState;
  String? syncError;
  int? remoteVersion;

  TransitionAlert({
    required this.id,
    required this.title,
    this.description = '',
    required this.audioType,
    this.recordedAudioPath,
    this.ttsText,
    this.messageText,
    this.audioUrl,
    this.countdownSeconds = 60,
    this.advanceTime = 0,
    List<String>? checklistItems,
    this.isScheduled = false,
    bool? isRecurring,
    this.isActive = true,
    this.scheduledHour,
    this.scheduledMinute,
    this.scheduledTime,
    List<int>? scheduledWeekdays,
    this.hasSound = true,
    this.soundVolume = 1.0,
    List<int>? vibrationPattern,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.notificationId,
    this.syncState = 'local',
    this.syncError,
    this.remoteVersion,
  })  : isRecurring = isRecurring ?? isScheduled,
        checklistItems = checklistItems ?? [],
        scheduledWeekdays = scheduledWeekdays ?? [],
        vibrationPattern = vibrationPattern ?? [0, 300, 200, 300],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Nome atual do campo de dias, mantido como alias para o código legado.
  List<int> get daysOfWeek => scheduledWeekdays;

  /// Texto efetivo que a notificação e o TTS devem usar.
  String get effectiveMessageText {
    final message = messageText?.trim();
    if (message != null && message.isNotEmpty) return message;
    return ttsText?.trim() ?? '';
  }

  int? get effectiveScheduledHour => scheduledHour ?? scheduledTime?.hour;
  int? get effectiveScheduledMinute => scheduledMinute ?? scheduledTime?.minute;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'audioType': audioType,
      'recordedAudioPath': recordedAudioPath,
      'ttsText': ttsText,
      'messageText': messageText ?? ttsText,
      'audioUrl': audioUrl,
      'countdownSeconds': countdownSeconds,
      'advanceTime': advanceTime,
      'checklistItems': checklistItems,
      'isScheduled': isScheduled,
      'isRecurring': isRecurring,
      'isActive': isActive,
      'scheduledTime': scheduledTime?.millisecondsSinceEpoch,
      'scheduledHour': effectiveScheduledHour,
      'scheduledMinute': effectiveScheduledMinute,
      'scheduledWeekdays': scheduledWeekdays,
      'daysOfWeek': scheduledWeekdays,
      'hasSound': hasSound,
      'soundVolume': soundVolume,
      'vibrationPattern': vibrationPattern,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'notificationId': notificationId,
      'syncState': syncState,
      'syncError': syncError,
      'remoteVersion': remoteVersion,
    };
  }

  factory TransitionAlert.fromMap(Map map) {
    final scheduledHour = _asInt(map['scheduledHour']);
    final scheduledMinute = _asInt(map['scheduledMinute']);
    final rawScheduledTime = _asInt(map['scheduledTime']);
    final scheduledTime = rawScheduledTime == null
        ? (scheduledHour == null || scheduledMinute == null
            ? null
            : DateTime(1970, 1, 1, scheduledHour, scheduledMinute))
        : DateTime.fromMillisecondsSinceEpoch(rawScheduledTime);
    final scheduled = map['isScheduled'] as bool? ?? false;
    final recurring = map['isRecurring'] as bool? ?? scheduled;
    final messageText =
        map['messageText'] as String? ?? map['ttsText'] as String?;

    return TransitionAlert(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      audioType: map['audioType'] as String? ?? 'tts',
      recordedAudioPath: map['recordedAudioPath'] as String?,
      ttsText: map['ttsText'] as String? ?? messageText,
      messageText: messageText,
      audioUrl: map['audioUrl'] as String?,
      countdownSeconds: _asInt(map['countdownSeconds']) ?? 60,
      advanceTime: _asInt(map['advanceTime']) ?? 0,
      checklistItems: _asStringList(map['checklistItems']),
      isScheduled: scheduled,
      isRecurring: recurring,
      isActive: map['isActive'] as bool? ?? true,
      scheduledHour: scheduledHour,
      scheduledMinute: scheduledMinute,
      scheduledTime: scheduledTime,
      scheduledWeekdays:
          _asIntList(map['daysOfWeek'] ?? map['scheduledWeekdays']),
      hasSound: map['hasSound'] as bool? ?? true,
      soundVolume: _asDouble(map['soundVolume']) ?? 1.0,
      vibrationPattern: _asIntList(map['vibrationPattern']).isEmpty
          ? [0, 300, 200, 300]
          : _asIntList(map['vibrationPattern']),
      createdAt: _asDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _asDateTime(map['updatedAt']) ?? DateTime.now(),
      notificationId: _asInt(map['notificationId']) ?? 0,
      syncState: map['syncState'] as String? ?? 'local',
      syncError: map['syncError'] as String?,
      remoteVersion: _asInt(map['remoteVersion']),
    );
  }
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

DateTime? _asDateTime(Object? value) {
  final milliseconds = _asInt(value);
  return milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

List<int> _asIntList(Object? value) {
  if (value is! List) return [];
  return value.whereType<num>().map((item) => item.toInt()).toList();
}

List<String> _asStringList(Object? value) {
  if (value is! List) return [];
  return value.map((item) => item.toString()).toList();
}
