import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/vault.dart';

/// PHASE14F: focused unit tests for the two pure, exported helpers the
/// image-upload flow added to `vault.dart` — `imageContentTypeForFilename`
/// and `kMaxImageUploadBytes`. `_VaultImage`, `_uploadImage`,
/// `_renameImage`, `_deleteImage`, and `_showImageMenu` are all
/// intentionally private to `vault.dart`/`viewall_images.dart` (Dart
/// privacy is per-file) and are exercised only through
/// `MediaRepository`/`ApiClient`, whose behavior — multipart filename/
/// content type, upload success/failure, list/get/rename/delete, and
/// 401/404/413/415/422/5xx/network propagation — is already fully covered
/// by `test/data/repositories/media/media_repository_test.dart` and
/// `test/core/network/api_client_upload_test.dart` from PHASE14E; neither
/// `MediaRepository` nor `ApiClient` was modified by PHASE14F, so that
/// coverage is not duplicated here.
void main() {
  group('imageContentTypeForFilename', () {
    test('maps every backend-supported image extension to its exact content type', () {
      // Matches ALLOWED_CONTENT_TYPES's image entries in
      // backend/app/services/media_service.py exactly — see PHASE14D
      // audit report, Section 2.
      expect(imageContentTypeForFilename('photo.jpg'), 'image/jpeg');
      expect(imageContentTypeForFilename('photo.jpeg'), 'image/jpeg');
      expect(imageContentTypeForFilename('photo.png'), 'image/png');
      expect(imageContentTypeForFilename('photo.gif'), 'image/gif');
      expect(imageContentTypeForFilename('photo.webp'), 'image/webp');
    });

    test('is case-insensitive on the extension', () {
      expect(imageContentTypeForFilename('PHOTO.JPG'), 'image/jpeg');
      expect(imageContentTypeForFilename('Photo.PNG'), 'image/png');
    });

    test('returns null for an unsupported extension rather than guessing', () {
      expect(imageContentTypeForFilename('document.pdf'), isNull);
      expect(imageContentTypeForFilename('clip.mp4'), isNull);
      expect(imageContentTypeForFilename('archive.heic'), isNull);
    });

    test('returns null for a filename with no extension', () {
      expect(imageContentTypeForFilename('noextension'), isNull);
    });
  });

  group('kMaxImageUploadBytes', () {
    test('matches the backend default max_upload_size_mb of 25MB (PHASE14D audit report, Section 2)', () {
      expect(kMaxImageUploadBytes, 25 * 1024 * 1024);
    });
  });
}
