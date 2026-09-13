import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'image_note.dart';
import 'dart:io';
// PHASE14F: `vault.dart` was already imported here (previously unused —
// see the PHASE14C/14D-era `flutter analyze` output) and now actually
// supplies imageContentTypeForFilename/kMaxImageUploadBytes, the two
// PHASE14F helpers that don't need to be file-private. `_VaultImage`
// itself and `_friendlyImageMediaError` are NOT reused from there — Dart
// privacy is per-file, so vault.dart's own leading-underscore
// declarations aren't visible here regardless of this import; each file
// keeps its own copy, exactly like `_ImageListItem`/`_showImageMenu`/
// `_showRenameDialog` were already independently duplicated between these
// two files before this phase.
import 'vault.dart';
import 'package:file_picker/file_picker.dart';
import 'core/network/api_exception.dart';
import 'data/models/media/media_asset_model.dart';
import 'data/repositories/media_repository.dart';
import 'custom_snackbar.dart';
// PHASE14I-F: suppresses a migrated legacy Hive image from this page's own
// merged list — see legacy_media_reconciliation.dart's doc.
import 'data/services/legacy_media_reconciliation.dart';

class ViewAllImagesPage extends StatefulWidget {
  const ViewAllImagesPage({Key? key}) : super(key: key);

  @override
  State<ViewAllImagesPage> createState() => _ViewAllImagesPageState();
}

class _ViewAllImagesPageState extends State<ViewAllImagesPage> {
  String _search = '';

  /// PHASE14F: this user's backend-hosted images, newest first — see
  /// `vault.dart`'s own `_remoteImages` doc. Loaded independently here
  /// (this page has its own `State`, and there is deliberately no shared/
  /// global media state anywhere in the app — no Provider/Riverpod/Bloc).
  List<MediaAssetModel> _remoteImages = [];

  @override
  void initState() {
    super.initState();
    _loadRemoteImages();
  }

  Future<void> _loadRemoteImages() async {
    try {
      final page = await MediaRepository.instance.list(mediaType: 'image', limit: 100, offset: 0);
      if (!mounted) return;
      setState(() { _remoteImages = page.items; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
    }
  }

  /// PHASE14F image creation — replaces the old direct
  /// `Hive.box<ImageNote>('image_notes').add(...)` call. See `vault.dart`'s
  /// `_uploadImage` for the full rationale; this is the same flow,
  /// independently implemented for this page's own state.
  Future<void> _uploadImage(String pickedPath, String pickedFilename) async {
    final file = File(pickedPath);
    if (!await file.exists()) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't find that image on your device.", icon: Icons.error_outline);
      return;
    }

    final contentType = imageContentTypeForFilename(pickedFilename);
    if (contentType == null) {
      if (!mounted) return;
      showCustomSnackBar(context, "That file type isn't supported.", icon: Icons.error_outline);
      return;
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      showCustomSnackBar(context, "Couldn't read that image. Please try again.", icon: Icons.error_outline);
      return;
    }

    if (bytes.length > kMaxImageUploadBytes) {
      if (!mounted) return;
      showCustomSnackBar(context, 'That image is too large (max 25MB).', icon: Icons.error_outline);
      return;
    }

    try {
      final created = await MediaRepository.instance.upload(
        fileBytes: bytes,
        filename: pickedFilename,
        contentType: contentType,
      );

      var result = created;
      try {
        result = await MediaRepository.instance.rename(mediaId: created.id, title: capitalizeIfNeeded(pickedFilename));
      } on ApiException {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Image uploaded, but its title could not be saved. You can rename it from the menu.',
            icon: Icons.info_outline,
          );
        }
      }

      if (!mounted) return;
      setState(() { _remoteImages = [result, ..._remoteImages]; });
    } on ApiException catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
    }
  }

  Future<void> _renameImage(_VaultImage item, String newTitle) async {
    if (item.remote != null) {
      try {
        final updated = await MediaRepository.instance.rename(mediaId: item.remote!.id, title: newTitle);
        if (!mounted) return;
        setState(() {
          _remoteImages = _remoteImages.map((m) => m.id == updated.id ? updated : m).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14F behavior.
    item.legacy!.title = capitalizeIfNeeded(newTitle);
    await item.legacy!.save();
  }

  Future<void> _deleteImage(_VaultImage item) async {
    if (item.remote != null) {
      try {
        await MediaRepository.instance.delete(item.remote!.id);
        if (!mounted) return;
        setState(() {
          _remoteImages = _remoteImages.where((m) => m.id != item.remote!.id).toList();
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        showCustomSnackBar(context, _friendlyImageMediaError(e), icon: Icons.error_outline);
      }
      return;
    }
    // Legacy Hive item — unchanged from the pre-PHASE14F behavior; see
    // PHASE14F implementation report, "Delete flow" limitation.
    await item.legacy!.delete();
  }

  void _showImageMenu(BuildContext context, _VaultImage item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            onTap: () async {
              Navigator.pop(context);
              final newTitle = await _showRenameDialog(context, item.title);
              if (newTitle != null && newTitle.isNotEmpty) {
                await _renameImage(item, newTitle);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await _deleteImage(item);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD9D0),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  SizedBox(width: 8),
                  Text('Images', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SearchBar(
                onAdd: () async {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    await _uploadImage(result.files.single.path!, result.files.single.name);
                  }
                },
                isRecording: false,
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: _VaultSectionCard(
                  child: ValueListenableBuilder(
                    valueListenable: Hive.box<ImageNote>('image_notes').listenable(),
                    builder: (context, Box<ImageNote> box, _) {
                      // PHASE14I-F: a legacy image whose migrated backend
                      // counterpart already exists in _remoteImages is
                      // left out of `merged` here — the Hive record
                      // itself is untouched (box.values is never written
                      // to). See legacy_media_reconciliation.dart.
                      final unmigratedLegacy = suppressMigratedLegacyItems(
                        legacyItems: box.values.toList(),
                        remoteItems: _remoteImages,
                        kind: LegacyMediaKind.image,
                        legacyIdOf: (n) => n.id,
                      );
                      final merged = <_VaultImage>[
                        ..._remoteImages.map((m) => _VaultImage.remote(m)),
                        ...unmigratedLegacy.map((n) => _VaultImage.legacy(n)),
                      ]..sort((a, b) => b.date.compareTo(a.date));
                      final filtered = merged
                          .where((item) => item.title.toLowerCase().contains(_search.toLowerCase()))
                          .toList();
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No images uploaded'));
                      }
                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8),
                        itemBuilder: (context, i) => _ImageListItem(
                          key: ValueKey(filtered[i].key),
                          item: filtered[i],
                          onMenu: () => _showImageMenu(context, filtered[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultSectionCard extends StatelessWidget {
  final Widget child;
  const _VaultSectionCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

/// PHASE14F: same shape as `vault.dart`'s own `_VaultImage` — file-private
/// on both sides (Dart privacy is per-file), so this is a deliberate,
/// small duplication rather than a shared import; see this file's own
/// import-comment for the two helpers that ARE shared.
class _VaultImage {
  const _VaultImage.remote(MediaAssetModel this.remote) : legacy = null;
  const _VaultImage.legacy(ImageNote this.legacy) : remote = null;

  final MediaAssetModel? remote;
  final ImageNote? legacy;

  String get title => legacy?.title ?? remote!.title ?? remote!.originalFilename ?? 'Untitled';
  DateTime get date => legacy?.date ?? remote!.createdAt;
  String get key => legacy != null ? 'legacy:${legacy!.id}' : 'remote:${remote!.id}';
}

String _friendlyImageMediaError(ApiException e) {
  if (e is ValidationException) {
    return "That image couldn't be saved — please check it and try again.";
  }
  if (e is NetworkException) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  if (e is UnauthorizedException) {
    return 'Your session has expired. Please log in again.';
  }
  if (e is NotFoundException) {
    return 'That image could not be found.';
  }
  if (e.statusCode == 413) {
    return 'That image is too large (max 25MB).';
  }
  if (e.statusCode == 415) {
    return "That image type isn't supported.";
  }
  return 'Something went wrong with that image. Please try again.';
}

class _ImageListItem extends StatelessWidget {
  final _VaultImage item;
  final VoidCallback onMenu;
  const _ImageListItem({super.key, required this.item, required this.onMenu});

  static Widget _placeholder({Widget? child}) => Container(
    width: 48,
    height: 48,
    color: Colors.black12,
    child: child == null ? null : Center(child: child),
  );

  Widget _buildThumbnail() {
    if (item.legacy != null) {
      return Image.file(
        File(item.legacy!.path),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey)),
      );
    }
    return FutureBuilder<MediaAssetModel>(
      future: MediaRepository.instance.get(item.remote!.id),
      builder: (context, snapshot) {
        final url = snapshot.data?.downloadUrl;
        if (snapshot.connectionState == ConnectionState.done && url != null) {
          return Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey)),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return _placeholder(child: const Icon(Icons.broken_image, color: Colors.grey));
        }
        return _placeholder(
          child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  void _openFullView(BuildContext context) {
    final Widget content;
    if (item.legacy != null) {
      content = Image.file(
        File(item.legacy!.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Padding(
          padding: EdgeInsets.all(32),
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );
    } else {
      content = FutureBuilder<MediaAssetModel>(
        future: MediaRepository.instance.get(item.remote!.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator());
          }
          final url = snapshot.data?.downloadUrl;
          if (url == null) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            );
          }
          return Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Padding(
              padding: EdgeInsets.all(32),
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            ),
          );
        },
      );
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: content),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Color(0xFFFDDED0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openFullView(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildThumbnail(),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.length > 10 ? item.title.substring(0, 10) + '...' : item.title,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(DateFormat('dd-MM-yy').format(item.date), style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.more_vert, color: Colors.grey),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

Future<String?> _showRenameDialog(BuildContext context, String currentTitle) async {
  final controller = TextEditingController(text: currentTitle);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Rename Image'),
      content: TextField(controller: controller),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Rename')),
      ],
    ),
  );
}

String capitalizeIfNeeded(String input) {
  if (input.isEmpty) return input;
  if (double.tryParse(input[0]) != null) return input;
  return input[0].toUpperCase() + input.substring(1);
}

class _SearchBar extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool isRecording;
  final ValueChanged<String>? onChanged;
  const _SearchBar({this.onAdd, this.isRecording = false, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: Icon(Icons.search, color: Colors.grey, size: 18),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: onAdd != null
              ? IconButton(
                  icon: Icon(isRecording ? Icons.stop : Icons.add, color: Color.fromARGB(255, 234, 152, 115), size: 22),
                  onPressed: onAdd,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minHeight: 32, minWidth: 32),
                )
              : null,
        ),
        style: TextStyle(fontSize: 13),
        onChanged: onChanged,
      ),
    );
  }
}
