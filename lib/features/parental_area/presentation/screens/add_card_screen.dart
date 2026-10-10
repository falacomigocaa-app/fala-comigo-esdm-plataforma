import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/media_storage_service.dart';
import '../../../../core/services/parental_session_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/secure_media_image.dart';
import '../../../aac_grid/data/providers/cards_provider.dart';
import '../../../aac_grid/domain/models/pictogram_card.dart';
import '../widgets/parental_ui.dart';

/// Tela usada pelos pais/educadores para cadastrar um novo cartão ou
/// editar um já existente (quando [existingCard] é informado).
class AddCardScreen extends ConsumerStatefulWidget {
  final PictogramCard? existingCard;

  const AddCardScreen({super.key, this.existingCard});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final TextEditingController _labelController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _selectedImagePath;
  String _category = 'personalizado';
  bool _isSaving = false;

  static const _settingsBox = 'app_settings';
  static const _draftImageKey = 'add_card_draft_image_path';
  static const _draftLabelKey = 'add_card_draft_label';
  static const _draftCategoryKey = 'add_card_draft_category';

  bool get _isEditing => widget.existingCard != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingCard;
    if (existing != null) {
      _labelController.text = existing.label;
      _category = existing.category;
      _selectedImagePath = existing.imagePath;
    }
    _recoverCameraResult();
  }

  /// O Android pode destruir a Activity enquanto a câmera está aberta.
  /// Nesse caso o image_picker entrega a foto por retrieveLostData quando o
  /// Flutter volta a inicializar. O rascunho no Hive também permite recuperar
  /// a imagem sem perder o preenchimento do formulário parental.
  Future<void> _recoverCameraResult() async {
    final box = Hive.box(_settingsBox);
    final draftPath = box.get(_draftImageKey) as String?;
    final draftLabel = box.get(_draftLabelKey) as String?;
    final draftCategory = box.get(_draftCategoryKey) as String?;
    if (draftLabel != null && _labelController.text.isEmpty) {
      _labelController.text = draftLabel;
    }
    if (draftCategory != null &&
        AppConstants.categoryLabels.containsKey(draftCategory)) {
      _category = draftCategory;
    }

    String? recoveredPath = draftPath;
    try {
      final lostData = await _picker.retrieveLostData();
      final lostFile = lostData.files?.isNotEmpty == true
          ? lostData.files!.first
          : lostData.file;
      if (lostFile != null) {
        recoveredPath = await MediaStorageService.persistFile(lostFile.path);
      }
    } catch (_) {
      // O rascunho já persistido continua disponível para a próxima abertura.
    }

    if (!mounted || recoveredPath == null) return;
    setState(() => _selectedImagePath = recoveredPath);
    await box.put(_draftImageKey, recoveredPath);
  }

  Future<void> _saveDraft() async {
    final box = Hive.box(_settingsBox);
    await box.put(_draftLabelKey, _labelController.text.trim());
    await box.put(_draftCategoryKey, _category);
  }

  Future<void> _clearDraft() async {
    final box = Hive.box(_settingsBox);
    await box.delete(_draftImageKey);
    await box.delete(_draftLabelKey);
    await box.delete(_draftCategoryKey);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final isCamera = source == ImageSource.camera;
    if (isCamera) ParentalSessionService.beginExternalActivity();
    try {
      await _saveDraft();
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) {
        if (isCamera) ParentalSessionService.completeExternalActivity();
        return;
      }
      try {
        final permanentPath = await MediaStorageService.persistFile(
          picked.path,
        );
        if (mounted) {
          setState(() => _selectedImagePath = permanentPath);
          await Hive.box(_settingsBox).put(_draftImageKey, permanentPath);
        }
      } on UnsupportedError catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'Mídia não disponível nesta plataforma.',
            ),
          ),
        );
      }
      if (isCamera) ParentalSessionService.completeExternalActivity();
    } catch (_) {
      if (isCamera) ParentalSessionService.completeExternalActivity();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar essa imagem.')),
      );
    }
  }

  Future<void> _saveCard() async {
    if (_isSaving) return;
    if (_selectedImagePath == null || _labelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolha uma foto e digite um nome para o cartão.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await ref.read(cardsListProvider.notifier).updateCard(
              id: widget.existingCard!.id,
              label: _labelController.text.trim(),
              imagePath: _selectedImagePath!,
              isCustomImage: true,
              category: _category,
            );
      } else {
        await ref.read(cardsListProvider.notifier).addCard(
              label: _labelController.text.trim(),
              imagePath: _selectedImagePath!,
              isCustomImage: true,
              category: _category,
            );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar o cartão.')),
      );
      return;
    }

    await _clearDraft();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Cartão' : 'Adicionar Cartão'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const ParentalInfoBanner(
                  icon: Icons.auto_awesome_outlined,
                  eyebrow: 'NOVO CARTÃO',
                  message:
                      'Escolha uma imagem simples e um nome curto. O nome será falado quando o cartão for usado.',
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: _selectedImagePath == null
                      ? 'Selecionar imagem do cartão'
                      : 'Trocar imagem do cartão',
                  hint: 'Abre opções de galeria ou câmera',
                  child: GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Escolher da Galeria'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_camera_outlined),
                              title: const Text('Tirar Foto'),
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Container(
                      height: 160,
                      width: 160,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.cardBorder,
                          width: 1.5,
                        ),
                      ),
                      child: _selectedImagePath == null
                          ? const Center(
                              child: Icon(
                                Icons.add_a_photo_outlined,
                                size: 40,
                                color: AppTheme.primary,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SecureMediaImage(
                                path: _selectedImagePath!,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _labelController,
                  decoration: parentalInputDecoration(
                    labelText: 'Nome do cartão (o que será falado)',
                    icon: Icons.record_voice_over_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: parentalInputDecoration(
                    labelText: 'Categoria',
                    icon: Icons.category_outlined,
                  ),
                  items: AppConstants.categoryLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _category = v ?? 'personalizado'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveCard,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      backgroundColor: AppTheme.accentGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isEditing ? 'Salvar alterações' : 'Salvar cartão',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
