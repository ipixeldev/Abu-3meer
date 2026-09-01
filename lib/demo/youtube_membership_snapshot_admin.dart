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
    String fileName,
  ) =>
      widget.importSnapshot?.call(bytes, fileName) ??
      widget.repository!.importYouTubeMembershipSnapshot(
        bytes: bytes,
        fileName: fileName,
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
        builder: (dialogContext) => AlertDialog(
          title: Text(
            abuText(
              dialogContext,
              'Replace membership snapshot?',
              'استبدال لقطة العضويات؟',
            ),
          ),
          content: Text(
            abuText(
              dialogContext,
              'Import the complete current-member list as UTF-8 CSV or TSV. This replaces the previous snapshot, so every linked channel missing from the file becomes a non-member.',
              'استورد القائمة الكاملة للأعضاء الحاليين بصيغة CSV أو TSV وبترميز UTF-8. هذا يستبدل اللقطة السابقة، لذلك ستصبح كل قناة مرتبطة غير موجودة في الملف غير عضو.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(abuText(dialogContext, 'CANCEL', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(abuText(dialogContext, 'IMPORT', 'استيراد')),
            ),
          ],
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
      final imported = await _import(bytes, file.name);
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
        'Expired snapshot · ${status.memberCount} members · import a fresh complete export.',
        'لقطة منتهية · ${status.memberCount} عضواً · استورد ملفاً كاملاً وحديثاً.',
      );
    }
    return abuText(
      context,
      '${status.memberCount} members · ${status.matchedUserCount} linked accounts matched · valid until $expires',
      '${status.memberCount} عضواً · تمت مطابقة ${status.matchedUserCount} حساباً مرتبطاً · صالحة حتى $expires',
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active ? Icons.table_view_rounded : Icons.upload_file_rounded,
              color: active ? _productionPrimary(context) : _gold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    abuText(
                      context,
                      'Membership CSV / TSV',
                      'ملف عضويات CSV / TSV',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    snapshot.connectionState == ConnectionState.waiting
                        ? abuText(
                            context,
                            'Checking snapshot…',
                            'جارٍ فحص اللقطة…',
                          )
                        : snapshot.hasError
                        ? productionErrorMessage(snapshot.error!)
                        : _summary(context, status!),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
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
              ),
            ),
          ],
        );
      },
    ),
  );
}
