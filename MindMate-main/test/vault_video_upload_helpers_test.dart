import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/vault.dart';

/// PHASE14H: focused unit tests for the two pure, exported helpers the
/// video-upload flow added to `vault.dart` — `videoContentTypeForFilename`
/// and `kMaxVideoUploadBytes` — same scope/rationale as PHASE14F/G's
/// `vault_image_upload_helpers_test.dart`/`vault_voice_upload_helpers_
/// test.dart`. `_VaultVideo`, `_uploadVideo`, `_renameVideo`,
/// `_deleteVideo`, `_showVideoMenu`, and `VideoPlayerDialog`'s retry logic
/// are all intentionally private/stateful and are exercised only through
/// `MediaRepository`, whose own upload/list/get/rename/delete/error-
/// propagation behavior is already fully covered by
/// `test/data/repositories/media/media_repository_test.dart` and
/// `test/core/network/api_client_upload_test.dart` from PHASE14E; neither
/// `MediaRepository` nor `ApiClient` was modified by PHASE14H, so that
/// coverage is not duplicated here. `VideoPlayerDialog`'s presigned-URL
/// retry behavior is likewise not independently unit-testable without a
/// real/faked `VideoPlayerController` and a widget-level test harness —
/// see the PHASE14H implementation report, "Limitations."
void main() {
  group('videoContentTypeForFilename', () {
    test('maps .mp4 to the one backend-supported video content type', () {
      // Matches ALLOWED_CONTENT_TYPES's single video entry in
      // backend/app/services/media_service.py exactly — see PHASE14D
      // audit report, Section 2.
      expect(videoContentTypeForFilename('clip.mp4'), 'video/mp4');
    });

    test('is case-insensitive on the extension', () {
      expect(videoContentTypeForFilename('CLIP.MP4'), 'video/mp4');
      expect(videoContentTypeForFilename('Clip.Mp4'), 'video/mp4');
    });

    test('rejects every other video container the picker can return, rather than guessing', () {
      // FileType.video (the existing picker filter) is a broad OS-level
      // filter that can return any of these — only .mp4 is ever sent to
      // the backend (PHASE14H spec: "do not send unsupported formats").
      expect(videoContentTypeForFilename('clip.mov'), isNull);
      expect(videoContentTypeForFilename('clip.mkv'), isNull);
      expect(videoContentTypeForFilename('clip.avi'), isNull);
      expect(videoContentTypeForFilename('clip.webm'), isNull);
    });

    test('returns null for a filename with no extension', () {
      expect(videoContentTypeForFilename('noextension'), isNull);
    });
  });

  group('kMaxVideoUploadBytes', () {
    test('matches the backend default max_upload_size_mb of 25MB (PHASE14D audit report, Section 2)', () {
      expect(kMaxVideoUploadBytes, 25 * 1024 * 1024);
    });
  });
}
