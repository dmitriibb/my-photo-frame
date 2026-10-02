import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'archive_export.dart';

enum _ExportAction { save, share }

/// Opens Android's save picker directly and always removes temporary archives.
Future<bool> saveArchiveToFiles(
  Future<ExportBundle> Function() createArchive,
) async {
  final bundle = await createArchive();
  try {
    final saved = await FilePicker.saveFile(
      fileName: bundle.file.uri.pathSegments.last,
      bytes: await bundle.file.readAsBytes(),
      mimeType: 'application/zip',
      dialogTitle: 'Save My Photo Frame archive',
    );
    return saved != null;
  } finally {
    await bundle.dispose();
  }
}

Future<void> showArchiveExportOptions(
  BuildContext context,
  Future<ExportBundle> Function() createArchive,
) async {
  final action = await showDialog<_ExportAction>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Export archive'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, _ExportAction.save),
          child: const Text('Save to Files'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, _ExportAction.share),
          child: const Text('Share'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  ExportBundle? bundle;
  try {
    if (action == _ExportAction.save) {
      final saved = await saveArchiveToFiles(createArchive);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Archive saved.')));
      }
    } else {
      bundle = await createArchive();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(bundle.file.path, mimeType: 'application/zip')],
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export archive: $error')),
      );
    }
  } finally {
    await bundle?.dispose();
  }
}
