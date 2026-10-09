import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../../core/services/media_storage_service.dart';
import '../../../../core/services/transition_alert_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../transition_alerts/data/providers/transition_alerts_provider.dart';
import '../../../transition_alerts/domain/models/transition_alert.dart';
import '../../../transition_alerts/domain/services/transition_alert_sync_service.dart';

const Map<int, String> _weekdayLabels = {
  1: 'D',
  2: 'S',
  3: 'T',
  4: 'Q',
  5: 'Q',
  6: 'S',
  7: 'S',
};

class TransitionAlertEditScreen extends ConsumerStatefulWidget {
  final TransitionAlert? existingAlert;

  const TransitionAlertEditScreen({super.key, this.existingAlert});

  @override
  ConsumerState<TransitionAlertEditScreen> createState() =>
      _TransitionAlertEditScreenState();
}

class _TransitionAlertEditScreenState
    extends ConsumerState<TransitionAlertEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ttsController;
  final TextEditingController _checklistInputController =
      TextEditingController();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  late String _alertId;
  late int _notificationId;
  late String _audioType;
  String? _recordedAudioPath;
  bool _isRecording = false;
  bool _isPlayingPreview = false;
  Completer<void>? _stopPreview;
  Future<void> Function()? _releaseActivePreview;

  late bool _isScheduled;
  late bool _isActive;
  late int _advanceMinutes;
  TimeOfDay? _scheduledTimeOfDay;
  late Set<int> _scheduledWeekdays;
  late int _countdownSeconds;
  late List<String> _checklistItems;

  bool get _isEditing => widget.existingAlert != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAlert;
    final notifier = ref.read(transitionAlertsListProvider.notifier);

    _alertId = existing?.id ?? notifier.generateId();
    _notificationId =
        existing?.notificationId ?? notifier.generateNotificationId();

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _audioType = existing?.audioType ?? 'tts';
    _ttsController = TextEditingController(text: existing?.ttsText ?? '');
    _recordedAudioPath = existing?.recordedAudioPath;

    _isScheduled = existing?.isScheduled ?? false;
    _isActive = existing?.isActive ?? true;
    _advanceMinutes = existing?.advanceTime ?? 0;
    _scheduledWeekdays = {...(existing?.scheduledWeekdays ?? [])};
    _countdownSeconds = existing?.countdownSeconds ?? 60;
    _checklistItems = [...(existing?.checklistItems ?? [])];

    if (existing?.scheduledHour != null && existing?.scheduledMinute != null) {
      _scheduledTimeOfDay = TimeOfDay(
        hour: existing!.scheduledHour!,
        minute: existing.scheduledMinute!,
      );
    }
  }

  @override
  void dispose() {
    final stopPreview = _stopPreview;
    if (stopPreview != null && !stopPreview.isCompleted) {
      stopPreview.complete();
    }
    final releasePreview = _releaseActivePreview;
    _releaseActivePreview = null;
    if (releasePreview != null) {
      unawaited(releasePreview().catchError((Object _) {}));
    }
    unawaited(_player.stop().catchError((Object _) {}));
    unawaited(_player.dispose().catchError((Object _) {}));
    _titleController.dispose();
    _descriptionController.dispose();
    _ttsController.dispose();
    _checklistInputController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<String> _recordingFilePath() async {
    return MediaStorageService.createTemporaryRecordingPath(_alertId);
  }

  Future<void> _toggleRecording() async {
    if (kIsWeb) return;
    if (_isRecording) {
      final path = await _recorder.stop();
      if (path != null) {
        final encryptedPath = await MediaStorageService.persistFile(path);
        await MediaStorageService.deleteTemporaryRecording(path);
        final previousPath = _recordedAudioPath;
        if (previousPath != null) {
          await MediaStorageService.deleteFile(previousPath);
        }
        setState(() {
          _isRecording = false;
          _recordedAudioPath = encryptedPath;
        });
      } else {
        setState(() => _isRecording = false);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'É preciso autorizar o uso do microfone para gravar.',
            ),
          ),
        );
      }
      return;
    }

    final path = await _recordingFilePath();
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _playPreview() async {
    if (kIsWeb || _recordedAudioPath == null || _isPlayingPreview) return;
    setState(() => _isPlayingPreview = true);
    final stopSignal = Completer<void>();
    Future<void> Function()? releasePreview;
    try {
      final preview = await MediaStorageService.materializeForReading(
        _recordedAudioPath!,
      );
      releasePreview =
          () => MediaStorageService.releaseMaterializedFile(preview);
      _releaseActivePreview = releasePreview;
      if (!mounted) return;

      _stopPreview = stopSignal;
      final completed = _player.onPlayerComplete.first.then((_) {});
      await _player.play(DeviceFileSource(preview.path));
      await Future.any<void>([completed, stopSignal.future]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Não foi possível reproduzir este áudio nesta plataforma.'),
          ),
        );
      }
    } finally {
      if (identical(_stopPreview, stopSignal)) _stopPreview = null;
      if (identical(_releaseActivePreview, releasePreview)) {
        _releaseActivePreview = null;
      }
      await releasePreview?.call();
      if (mounted) setState(() => _isPlayingPreview = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTimeOfDay ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _scheduledTimeOfDay = picked);
    }
  }

  void _addChecklistItem() {
    final text = _checklistInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklistItems.add(text);
      _checklistInputController.clear();
    });
  }

  TransitionAlert _buildAlert() {
    return TransitionAlert(
      id: _alertId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      audioType: _audioType,
      recordedAudioPath: _recordedAudioPath,
      ttsText: _ttsController.text.trim(),
      messageText: _ttsController.text.trim(),
      countdownSeconds: _countdownSeconds,
      checklistItems: _checklistItems,
      isScheduled: _isScheduled,
      isRecurring: _isScheduled,
      isActive: _isActive,
      advanceTime: _advanceMinutes,
      scheduledHour: _scheduledTimeOfDay?.hour,
      scheduledMinute: _scheduledTimeOfDay?.minute,
      scheduledTime: _scheduledTimeOfDay == null
          ? null
          : DateTime(
              1970,
              1,
              1,
              _scheduledTimeOfDay!.hour,
              _scheduledTimeOfDay!.minute,
            ),
      scheduledWeekdays: _scheduledWeekdays.toList(),
      notificationId: _notificationId,
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dê um nome para o alerta antes de salvar.'),
        ),
      );
      return;
    }
    if (_audioType != 'gravado' && _recordedAudioPath != null) {
      await MediaStorageService.deleteFile(_recordedAudioPath!);
      _recordedAudioPath = null;
    }
    final alert = _buildAlert();
    try {
      if (alert.isActive && (alert.isScheduled || alert.isRecurring)) {
        await TransitionAlertService.instance.ensureSchedulingReady();
      }
    } on TransitionAlertPermissionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Verificar',
              onPressed: () async {
                final status = await TransitionAlertService.instance
                    .checkPermissionStatus();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(status)),
                  );
                }
              },
            ),
          ),
        );
      return;
    }
    if (_isEditing) {
      await ref.read(transitionAlertsListProvider.notifier).updateAlert(alert);
    } else {
      await ref.read(transitionAlertsListProvider.notifier).addAlert(alert);
    }
    var scheduleFailed = false;
    try {
      await TransitionAlertService.instance.scheduleRecurring(alert);
    } catch (error) {
      scheduleFailed = true;
      alert.isActive = false;
      await ref.read(transitionAlertsListProvider.notifier).updateAlert(alert);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agendamento recusado: $error'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
    unawaited(TransitionAlertSyncService.enqueueUpsert(alert));
    if (!mounted) return;
    if (scheduleFailed) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Alerta' : 'Novo Alerta'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.professionalBackground,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: AppTheme.professionalAccent,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditing
                        ? 'Atualize o alerta conforme a rotina atual. As mudanças ficam salvas localmente.'
                        : 'Crie um aviso previsível para apoiar a próxima mudança de atividade.',
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Nome do alerta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Ex: Hora do banho',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
              hintText: 'Explique o que acontece nesta transição.',
              border: OutlineInputBorder(),
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Mensagem de áudio',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Gravação de voz e notificações agendadas não estão habilitadas na prévia Web.',
                style: TextStyle(color: Colors.deepOrange),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (!kIsWeb)
                ChoiceChip(
                  label: const Text('Gravar minha voz'),
                  selected: _audioType == 'gravado',
                  onSelected: (_) => setState(() => _audioType = 'gravado'),
                ),
              ChoiceChip(
                label: const Text('Digitar (o app fala)'),
                selected: _audioType == 'tts',
                onSelected: (_) => setState(() => _audioType = 'tts'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_audioType == 'gravado')
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: kIsWeb ? null : _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'Parar' : 'Gravar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isRecording ? Colors.redAccent : AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                if (_recordedAudioPath != null)
                  IconButton(
                    onPressed:
                        kIsWeb || _isPlayingPreview ? null : _playPreview,
                    icon: const Icon(
                      Icons.play_circle,
                      color: AppTheme.accentGreen,
                      size: 32,
                    ),
                    tooltip: 'Ouvir gravação',
                  ),
              ],
            )
          else
            TextField(
              controller: _ttsController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ex: Vamos guardar os brinquedos e ir para o banho!',
                border: OutlineInputBorder(),
              ),
            ),
          const Divider(height: 32),
          const Text(
            'Contagem visual',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '$_countdownSeconds segundos',
            style: const TextStyle(color: Colors.grey),
          ),
          Slider(
            value: _countdownSeconds.toDouble(),
            min: 10,
            max: 300,
            divisions: 29,
            activeColor: AppTheme.primary,
            onChanged: (v) => setState(() => _countdownSeconds = v.round()),
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Alerta ativo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: _isActive,
                activeThumbColor: AppTheme.primary,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Repetir em horário fixo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: _isScheduled,
                activeThumbColor: AppTheme.primary,
                onChanged:
                    kIsWeb ? null : (v) => setState(() => _isScheduled = v),
              ),
            ],
          ),
          if (_isScheduled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time),
              label: Text(
                _scheduledTimeOfDay == null
                    ? 'Escolher horário'
                    : _scheduledTimeOfDay!.format(context),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _advanceMinutes,
              decoration: const InputDecoration(
                labelText: 'Avisar com antecedência',
                border: OutlineInputBorder(),
              ),
              items: const [0, 1, 5, 10, 15, 30]
                  .map(
                    (minutes) => DropdownMenuItem<int>(
                      value: minutes,
                      child: Text(
                        minutes == 0
                            ? 'No horário da atividade'
                            : '$minutes min antes',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _advanceMinutes = value);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: _weekdayLabels.entries.map((entry) {
                final selected = _scheduledWeekdays.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: selected,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _scheduledWeekdays.add(entry.key);
                    } else {
                      _scheduledWeekdays.remove(entry.key);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
          const Divider(height: 32),
          const Text(
            'Checklist depois do alerta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Dica: comece cada item com um emoji, ex: "🧸 Guardar os brinquedos".',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _checklistInputController,
                  decoration: const InputDecoration(
                    hintText: '🧸 Guardar os brinquedos',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addChecklistItem(),
                ),
              ),
              IconButton(
                onPressed: _addChecklistItem,
                icon: const Icon(
                  Icons.add_circle,
                  color: AppTheme.primary,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _checklistItems.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_checklistItems[i]),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () => setState(() => _checklistItems.removeAt(i)),
              ),
            ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Salvar alerta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
