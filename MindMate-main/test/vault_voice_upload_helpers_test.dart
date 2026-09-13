import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/vault.dart';

/// PHASE14G: focused unit tests for the two pure, exported helpers the
/// voice-upload flow added to `vault.dart` — `voiceContentTypeForFilename`
/// and `kMaxVoiceUploadBytes` — same scope/rationale as PHASE14F's
/// `vault_image_upload_helpers_test.dart`. `_VoiceItem`,
/// `_uploadVoiceNote`, `_renameVoiceNote`, `_deleteVoiceNote`,
/// `_showVoiceNoteMenu`, and `_playRemoteVoiceNote` are all intentionally
/// private to `vault.dart` (Dart privacy is per-file) and are exercised
/// only through `MediaRepository`, whose own upload/list/get/rename/
/// delete/error-propagation behavior is already fully covered by
/// `test/data/repositories/media/media_repository_test.dart` and
/// `test/core/network/api_client_upload_test.dart` from PHASE14E; neither
/// `MediaRepository` nor `ApiClient` was modified by PHASE14G, so that
/// coverage is not duplicated here. `_playRemoteVoiceNote`'s presigned-URL
/// retry behavior is likewise not independently unit-testable without a
/// real/faked `AudioPlayer` and a widget-level test harness — see the
/// PHASE14G implementation report, "Limitations."
void main() {
  group('voiceContentTypeForFilename', () {
    test('maps every backend-supported voice extension to its exact content type', () {
      // Matches ALLOWED_CONTENT_TYPES's voice entries in
      // backend/app/services/media_service.py exactly — see PHASE14D
      // audit report, Section 2. Recordings are always .m4a; imports are
      // restricted by the file picker to exactly this extension set.
      expect(voiceContentTypeForFilename('recording.m4a'), 'audio/mp4');
      expect(voiceContentTypeForFilename('song.mp3'), 'audio/mpeg');
      expect(voiceContentTypeForFilename('clip.wav'), 'audio/wav');
      expect(voiceContentTypeForFilename('clip.aac'), 'audio/aac');
      expect(voiceContentTypeForFilename('clip.opus'), 'audio/opus');
      expect(voiceContentTypeForFilename('clip.ogg'), 'audio/ogg');
    });

    test('is case-insensitive on the extension', () {
      expect(voiceContentTypeForFilename('RECORDING.M4A'), 'audio/mp4');
      expect(voiceContentTypeForFilename('Song.Mp3'), 'audio/mpeg');
    });

    test('returns null for an unsupported extension rather than guessing', () {
      expect(voiceContentTypeForFilename('video.mp4'), isNull);
      expect(voiceContentTypeForFilename('document.pdf'), isNull);
      expect(voiceContentTypeForFilename('image.png'), isNull);
    });

    test('returns null for a filename with no extension', () {
      expect(voiceContentTypeForFilename('noextension'), isNull);
    });
  });

  group('kMaxVoiceUploadBytes', () {
    test('matches the backend default max_upload_size_mb of 25MB (PHASE14D audit report, Section 2)', () {
      expect(kMaxVoiceUploadBytes, 25 * 1024 * 1024);
    });
  });
}
