part of 'fan_league_app.dart';

typedef YouTubeMembershipSnapshotLoader =
    Future<YouTubeMembershipSnapshotStatus> Function();
typedef YouTubeMembershipSnapshotImporter =
    Future<YouTubeMembershipSnapshotStatus> Function(
      Uint8List bytes,
      String fileName,
    );
typedef YouTubeMembershipSnapshotPicker = Future<XFile?> Function();

/// Profile-accessible upload surface for moderators and administrators.
///
/// Role visibility is enforced by the profile screen and authorization is
/// enforced again by the backend. The selected source file is streamed to the
/// API; this client never stores a second local copy.
class MembershipSnapshotProfilePanel extends StatelessWidget {
  const MembershipSnapshotProfilePanel({super.key, required this.repository});

  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('profile-membership-snapshot-upload'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _gold.withValues(alpha: .4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: _gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                abuText(
                  context,
                  'MEMBERSHIP LIST ACCESS',
                  'إدارة قائمة العضويات',
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          abuText(
            context,
            'Upload the complete current YouTube members CSV/TSV here. The app sends it directly to the ABU 3MEER server over encrypted HTTPS; it does not save another copy on this device.',
            'ارفع هنا ملف CSV/TSV الكامل والحالي لأعضاء يوتيوب. يرسله التطبيق مباشرة إلى خادم ABU 3MEER عبر اتصال HTTPS مشفّر، ولا يحفظ نسخة أخرى على هذا الجهاز.',
          ),
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        AdminYouTubeMembershipSnapshotCard(repository: repository),
      ],
    ),
  );
}

/// Admin-managed source of truth for active YouTube channel memberships.
class AdminYouTubeMembershipSnapshotCard extends StatefulWidget {
  const AdminYouTubeMembershipSnapshotCard({
    super.key,
    this.repository,
    this.loadStatus,
    this.importSnapshot,
    this.pickFile,
    this.onImported,
  }) : assert(
         repository != null ||
             (loadStatus != null && importSnapshot != null && pickFile != null),
       );

  final ProductionRepository? repository;
  final YouTubeMembershipSnapshotLoader? loadStatus;
  final YouTubeMembershipSnapshotImporter? importSnapshot;
  final YouTubeMembershipSnapshotPicker? pickFile;
  final VoidCallback? onImported;

  @override
  State<AdminYouTubeMembershipSnapshotCard> createState() =>
      _AdminYouTubeMembershipSnapshotCardState();
}

class _AdminYouTubeMembershipSnapshotCardState
    extends State<AdminYouTubeMembershipSnapshotCard> {
  late Future<YouTubeMembershipSnapshotStatus> _status;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _status = _load();
  }

  Future<YouTubeMembershipSnapshotStatus> _load() =>
      widget.loadStatus?.call() ??
      widget.repository!.fetchYouTubeMembershipSnapshotStatus();

  Future<XFile?> _pick() async {
    if (widget.pickFile != null) return widget.pickFile!.call();
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'YouTube membership CSV or TSV',
          extensions: ['csv', 'tsv'],
          mimeTypes: ['text/csv', 'text/tab-separated-values'],
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'public.tab-separated-values-text',
          ],
        ),
      ],
    );
  }

  Future<YouTubeMembershipSnapshotStatus> _import(
    Uint8List bytes,
    String fileName, {
    bool confirmLargeDecrease = false,
  }) {
    if (widget.importSnapshot != null) {
      return widget.importSnapshot!(bytes, fileName);
    }
    return widget.repository!.importYouTubeMembershipSnapshot(
      bytes: bytes,
      fileName: fileName,
      confirmLargeDecrease: confirmLargeDecrease,
    );
  }

  bool _requiresLargeDecreaseConfirmation(Object error) =>
      error is AbuApiException &&
      error.statusCode == 409 &&
      error.details.toString().contains(
        'youtube_snapshot_large_decrease_confirmation_required',
      );

  Future<void> _selectAndImport() async {
    if (_uploading) return;
    try {
      final file = await _pick();
      if (file == null || !mounted) return;
      final extension = file.name.split('.').last.toLowerCase();
      if (extension == 'xls' || extension == 'xlsx' || extension == 'xlsm') {
        throw StateError(
          abuText(
            context,
            'Excel files are not accepted. Export the sheet as UTF-8 CSV or TSV first.',
            'ملفات Excel غير مقبولة. صدّر الجدول أولاً بصيغة CSV أو TSV بترميز UTF-8.',
          ),
        );
      }
      if (!const {'csv', 'tsv'}.contains(extension)) {
        throw StateError(
          abuText(
            context,
            'Choose a .csv or .tsv YouTube membership export.',
            'اختر ملف عضويات يوتيوب بصيغة .csv أو .tsv.',
          ),
        );
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _MembershipSnapshotConfirmationDialog(
          title: abuText(
            dialogContext,
            'Replace membership snapshot?',
            'استبدال لقطة العضويات؟',
          ),
          body: abuText(
            dialogContext,
            'Import “${file.name}” as the complete current-member UTF-8 CSV/TSV list. This replaces the previous snapshot, so every linked channel missing from the file becomes a non-member.',
            'استورد «${file.name}» بوصفه قائمة CSV/TSV الكاملة للأعضاء الحاليين بترميز UTF-8. سيستبدل هذا اللقطة السابقة، ولذلك ستصبح كل قناة مرتبطة غير موجودة في الملف غير عضو.',
          ),
          confirmLabel: abuText(dialogContext, 'IMPORT', 'استيراد'),
          cancelLabel: abuText(dialogContext, 'CANCEL', 'إلغاء'),
          icon: Icons.upload_file_rounded,
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError(
          abuText(
            context,
            'The membership snapshot must be 5 MB or smaller.',
            'يجب ألا يتجاوز ملف العضويات 5 ميجابايت.',
          ),
        );
      }
      late YouTubeMembershipSnapshotStatus imported;
      try {
        imported = await _import(bytes, file.name);
      } catch (error) {
        if (!_requiresLargeDecreaseConfirmation(error) || !mounted) rethrow;
        final confirmLargeDecrease = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => _MembershipSnapshotConfirmationDialog(
            title: abuText(
              dialogContext,
              'Large membership decrease',
              'انخفاض كبير في العضويات',
            ),
            body:
                '${productionErrorMessage(error)}\n\n${abuText(dialogContext, 'Only continue if this is the complete current YouTube export. Missing channels will immediately become lapsed.', 'تابع فقط إذا كان هذا هو ملف يوتيوب الحالي والكامل. ستصبح القنوات غير الموجودة منتهية العضوية فوراً.')}',
            confirmLabel: abuText(
              dialogContext,
              'CONFIRM COMPLETE EXPORT',
              'تأكيد الملف الكامل',
            ),
            cancelLabel: abuText(dialogContext, 'CANCEL', 'إلغاء'),
            icon: Icons.warning_amber_rounded,
            warning: true,
          ),
        );
        if (confirmLargeDecrease != true || !mounted) {
          setState(() => _uploading = false);
          return;
        }
        imported = await _import(bytes, file.name, confirmLargeDecrease: true);
      }
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _status = Future.value(imported);
      });
      widget.onImported?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'Imported ${imported.memberCount} members; ${imported.matchedUserCount} linked app accounts matched.',
              'تم استيراد ${imported.memberCount} عضواً ومطابقة ${imported.matchedUserCount} حساباً مرتبطاً في التطبيق.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final message = error is StateError
          ? error.message.toString()
          : productionErrorMessage(error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _summary(
    BuildContext context,
    YouTubeMembershipSnapshotStatus status,
  ) {
    if (status.state == YouTubeMembershipSnapshotState.notImported) {
      return abuText(
        context,
        'No membership snapshot imported. Upload the complete UTF-8 YouTube members CSV/TSV export.',
        'لم يتم استيراد لقطة العضويات. ارفع ملف CSV/TSV الكامل لأعضاء يوتيوب بترميز UTF-8.',
      );
    }
    final expires = status.expiresAt == null
        ? ''
        : MaterialLocalizations.of(context).formatFullDate(status.expiresAt!);
    if (status.state == YouTubeMembershipSnapshotState.expired) {
      return abuText(
        context,
        'Stale snapshot still in use · ${status.memberCount} members · import a fresh complete export for accurate changes.',
        'لقطة قديمة ما زالت مستخدمة · ${status.memberCount} عضواً · استورد ملفاً كاملاً وحديثاً لتحديث التغييرات بدقة.',
      );
    }
    return abuText(
      context,
      '${status.memberCount} members · ${status.matchedUserCount} linked accounts matched · fresh through $expires',
      '${status.memberCount} عضواً · تمت مطابقة ${status.matchedUserCount} حساباً مرتبطاً · حديثة حتى $expires',
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: FutureBuilder<YouTubeMembershipSnapshotStatus>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final active = status?.isActive == true;
        final statusIcon = Icon(
          active ? Icons.table_view_rounded : Icons.upload_file_rounded,
          color: active ? _productionPrimary(context) : _gold,
        );
        final title = Text(
          abuText(context, 'Membership CSV / TSV', 'ملف عضويات CSV / TSV'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        );
        final summary = Text(
          key: const Key('membership-snapshot-summary'),
          snapshot.connectionState == ConnectionState.waiting
              ? abuText(context, 'Checking snapshot…', 'جارٍ فحص اللقطة…')
              : snapshot.hasError
              ? productionErrorMessage(snapshot.error!)
              : _summary(context, status!),
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
        );
        final uploadButton = OutlinedButton.icon(
          key: const Key('membership-snapshot-upload-button'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          ),
          onPressed: _uploading ? null : _selectAndImport,
          icon: _uploading
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_upload_outlined, size: 18),
          label: Text(
            abuText(
              context,
              active ? 'REPLACE' : 'IMPORT CSV / TSV',
              active ? 'استبدال' : 'استيراد CSV / TSV',
            ),
            textAlign: TextAlign.center,
          ),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      statusIcon,
                      const SizedBox(width: 10),
                      Expanded(child: title),
                    ],
                  ),
                  const SizedBox(height: 8),
                  summary,
                  const SizedBox(height: 12),
                  uploadButton,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusIcon,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 3), summary],
                  ),
                ),
                const SizedBox(width: 12),
                uploadButton,
              ],
            );
          },
        );
      },
    ),
  );
}

class _MembershipSnapshotConfirmationDialog extends StatelessWidget {
  const _MembershipSnapshotConfirmationDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    this.warning = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height -
        media.padding.vertical -
        media.viewInsets.bottom -
        32;
    final maxHeight = availableHeight.clamp(180.0, 720.0).toDouble();
    final accent = warning ? _gold : _productionPrimary(context);

    return Dialog(
      key: const Key('membership-snapshot-confirmation-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cancel = TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelLabel, textAlign: TextAlign.center),
                  );
                  final confirm = FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(confirmLabel, textAlign: TextAlign.center),
                  );
                  if (constraints.maxWidth < 410) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [confirm, const SizedBox(height: 6), cancel],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [cancel, const SizedBox(width: 8), confirm],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
