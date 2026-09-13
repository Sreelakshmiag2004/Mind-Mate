import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/media/media_asset_model.dart';

Map<String, dynamic> _listItemJson({
  String id = 'a1b2c3',
  String mediaType = 'image',
  String? originalFilename = 'my photo.png',
  String? title,
  String contentType = 'image/png',
  int fileSize = 12345,
  int? durationSeconds,
  String createdAt = '2025-01-06T09:15:00+00:00',
  String? legacySource,
  String? legacyCreatedAt,
}) => {
  'id': id,
  'media_type': mediaType,
  'original_filename': originalFilename,
  'title': title,
  'content_type': contentType,
  'file_size': fileSize,
  'duration_seconds': durationSeconds,
  'created_at': createdAt,
  'legacy_source': legacySource,
  if (legacyCreatedAt != null) 'legacy_created_at': legacyCreatedAt,
};

void main() {
  group('MediaAssetModel.fromJson — metadata', () {
    test('parses normal image metadata correctly', () {
      final asset = MediaAssetModel.fromJson(_listItemJson());

      expect(asset.id, 'a1b2c3');
      expect(asset.mediaType, 'image');
      expect(asset.originalFilename, 'my photo.png');
      expect(asset.contentType, 'image/png');
      expect(asset.fileSize, 12345);
    });

    test(
      'a null title parses as null (never renamed yet — not an error state)',
      () {
        final asset = MediaAssetModel.fromJson(_listItemJson(title: null));

        expect(asset.title, isNull);
      },
    );

    test('a set title parses correctly', () {
      final asset = MediaAssetModel.fromJson(
        _listItemJson(title: 'Beach trip'),
      );

      expect(asset.title, 'Beach trip');
    });

    test(
      'a null duration_seconds parses as null (image/video with no duration)',
      () {
        final asset = MediaAssetModel.fromJson(
          _listItemJson(durationSeconds: null),
        );

        expect(asset.durationSeconds, isNull);
      },
    );

    test('a set duration_seconds (voice) parses correctly', () {
      final asset = MediaAssetModel.fromJson(
        _listItemJson(mediaType: 'voice', durationSeconds: 42),
      );

      expect(asset.mediaType, 'voice');
      expect(asset.durationSeconds, 42);
    });

    test(
      'created_at parses into a real DateTime, consistent with the rest of the project',
      () {
        final asset = MediaAssetModel.fromJson(
          _listItemJson(createdAt: '2025-01-06T09:15:00+00:00'),
        );

        expect(asset.createdAt, DateTime.parse('2025-01-06T09:15:00+00:00'));
      },
    );
  });

  group('MediaAssetModel.fromJson — list vs. detail shape', () {
    test('a list-item (MediaAssetRead) response has no download_url', () {
      final asset = MediaAssetModel.fromJson(_listItemJson());

      expect(asset.downloadUrl, isNull);
      expect(asset.downloadUrlExpiresInSeconds, isNull);
    });

    test(
      'a detail (MediaAssetDetail) response carries download_url and its expiry',
      () {
        final json = {
          ..._listItemJson(),
          'download_url':
              'https://storage.example/bucket/image/u1/abc.png?X-Amz-Signature=...',
          'download_url_expires_in_seconds': 900,
        };

        final asset = MediaAssetModel.fromJson(json);

        expect(
          asset.downloadUrl,
          'https://storage.example/bucket/image/u1/abc.png?X-Amz-Signature=...',
        );
        expect(asset.downloadUrlExpiresInSeconds, 900);
      },
    );
  });

  group('MediaAssetModel.fromJson — PHASE14I-C legacy fields', () {
    test(
      'a null legacy_source parses as null (an ordinary, non-migrated upload)',
      () {
        final asset = MediaAssetModel.fromJson(_listItemJson());

        expect(asset.legacySource, isNull);
        expect(asset.legacyCreatedAt, isNull);
      },
    );

    test(
      'a migrated item\'s legacy_source and legacy_created_at parse correctly',
      () {
        final asset = MediaAssetModel.fromJson(
          _listItemJson(
            legacySource: 'image:abc',
            legacyCreatedAt: '2020-06-15T05:00:00+00:00',
          ),
        );

        expect(asset.legacySource, 'image:abc');
        expect(
          asset.legacyCreatedAt,
          DateTime.parse('2020-06-15T05:00:00+00:00'),
        );
      },
    );
  });

  group('MediaAssetModel.fromJson — never carries fields it must not', () {
    test(
      'does not decode user_id, object_key, or updated_at even if present in the JSON',
      () {
        final json = {
          ..._listItemJson(),
          'user_id': 'some-user-id',
          'object_key': 'image/some-user-id/deadbeef.png',
          'updated_at': '2025-01-07T09:15:00+00:00',
        };

        final asset = MediaAssetModel.fromJson(json);

        expect(asset.toJson().containsKey('user_id'), isFalse);
        expect(asset.toJson().containsKey('object_key'), isFalse);
        expect(asset.toJson().containsKey('updated_at'), isFalse);
      },
    );
  });

  group('MediaAssetModel.toJson', () {
    test('round-trips every decoded field, list-shaped (no download_url)', () {
      final asset = MediaAssetModel.fromJson(
        _listItemJson(title: 'Renamed', durationSeconds: 10),
      );

      final roundTripped = MediaAssetModel.fromJson(asset.toJson());

      expect(roundTripped.id, asset.id);
      expect(roundTripped.mediaType, asset.mediaType);
      expect(roundTripped.originalFilename, asset.originalFilename);
      expect(roundTripped.title, asset.title);
      expect(roundTripped.contentType, asset.contentType);
      expect(roundTripped.fileSize, asset.fileSize);
      expect(roundTripped.durationSeconds, asset.durationSeconds);
      expect(roundTripped.createdAt, asset.createdAt);
      expect(roundTripped.legacySource, asset.legacySource);
      expect(roundTripped.legacyCreatedAt, asset.legacyCreatedAt);
      expect(roundTripped.downloadUrl, isNull);
    });

    test('round-trips a migrated item\'s legacy_source/legacy_created_at', () {
      final asset = MediaAssetModel.fromJson(
        _listItemJson(
          legacySource: 'voice:xyz',
          legacyCreatedAt: '2020-06-15T05:00:00+00:00',
        ),
      );

      final roundTripped = MediaAssetModel.fromJson(asset.toJson());

      expect(roundTripped.legacySource, 'voice:xyz');
      expect(
        roundTripped.legacyCreatedAt,
        DateTime.parse('2020-06-15T05:00:00+00:00'),
      );
    });

    test('round-trips a detail-shaped asset, including download_url', () {
      final asset = MediaAssetModel.fromJson({
        ..._listItemJson(),
        'download_url': 'https://storage.example/x?sig=y',
        'download_url_expires_in_seconds': 900,
      });

      final roundTripped = MediaAssetModel.fromJson(asset.toJson());

      expect(roundTripped.downloadUrl, 'https://storage.example/x?sig=y');
      expect(roundTripped.downloadUrlExpiresInSeconds, 900);
    });
  });

  group('MediaAssetPage.fromJson', () {
    test(
      'parses items/total/limit/offset from a Page[MediaAssetRead] response',
      () {
        final json = {
          'items': [
            _listItemJson(id: 'a'),
            _listItemJson(id: 'b', mediaType: 'voice'),
          ],
          'total': 2,
          'limit': 30,
          'offset': 0,
        };

        final page = MediaAssetPage.fromJson(json);

        expect(page.items, hasLength(2));
        expect(page.items[0].id, 'a');
        expect(page.items[1].mediaType, 'voice');
        expect(page.total, 2);
        expect(page.limit, 30);
        expect(page.offset, 0);
      },
    );

    test('parses an empty page correctly', () {
      final page = MediaAssetPage.fromJson({
        'items': [],
        'total': 0,
        'limit': 30,
        'offset': 0,
      });

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });
  });
}
