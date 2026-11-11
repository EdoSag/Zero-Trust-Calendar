import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// A MIME type from a file name, for the common kinds people attach.
String? mimeTypeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'ics': 'text/calendar',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
  }[ext];
}

String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
  return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
}

/// One attached file: name and size; tap to open it (decrypted on this
/// phone, then handed to an app the user picks).
class AttachmentTile extends ConsumerWidget {
  const AttachmentTile({super.key, required this.attachment, this.onRemove});

  final Map<String, Object?> attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ZtAttachmentRef? parsed;
    try {
      parsed = ZtAttachmentRef.fromJson(attachment);
    } on Object {
      parsed = null;
    }
    final name = parsed?.name ?? context.l10n.attachment;
    final isImage = (parsed?.mimeType ?? '').startsWith('image/');
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      leading: Icon(isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: parsed == null ? null : Text(formatBytes(parsed.size)),
      onTap: parsed == null ? null : () => openAttachment(context, ref, parsed!),
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: context.l10n.removeAttachment,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
    );
  }
}

/// Decrypts [attachment] and shows it: images in the app, other files
/// through the share sheet ("Open with").
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  ZtAttachmentRef attachment,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final attachments = await ref.read(ztAttachmentsProvider.future);
    final bytes = await attachments.read(attachment);
    if ((attachment.mimeType ?? '').startsWith('image/')) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(attachment.name ?? context.l10n.image)),
            body: InteractiveViewer(child: Center(child: Image.memory(bytes))),
          ),
        ),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${attachment.name ?? attachment.id}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: attachment.mimeType)]),
    );
  } on AttachmentNotFound {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          currentL10n.thisFileHasntFinishedUploading,
        ),
      ),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(currentL10n.couldNotOpenFile('$e'))));
  }
}
