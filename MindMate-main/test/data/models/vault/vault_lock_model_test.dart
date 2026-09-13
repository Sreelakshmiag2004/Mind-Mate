import 'package:flutter_test/flutter_test.dart';
import 'package:mindmate/data/models/vault/vault_lock_model.dart';

Map<String, dynamic> _stateJson({
  bool configured = true,
  String? lastViewedAt = '2025-01-06T09:15:00+00:00',
  String? previousViewedAt,
}) => {
  'configured': configured,
  'last_viewed_at': lastViewedAt,
  'previous_viewed_at': previousViewedAt,
};

void main() {
  group('VaultLockModel.fromJson', () {
    test('configured true parses as true', () {
      final state = VaultLockModel.fromJson(_stateJson(configured: true));

      expect(state.configured, isTrue);
    });

    test('configured false parses as false', () {
      final state = VaultLockModel.fromJson(
        _stateJson(configured: false, lastViewedAt: null, previousViewedAt: null),
      );

      expect(state.configured, isFalse);
    });

    test('null timestamps parse as null (never-configured / never-unlocked state)', () {
      final state = VaultLockModel.fromJson(
        _stateJson(configured: false, lastViewedAt: null, previousViewedAt: null),
      );

      expect(state.lastViewedAt, isNull);
      expect(state.previousViewedAt, isNull);
    });

    test('a valid last_viewed_at parses into a real DateTime', () {
      final state = VaultLockModel.fromJson(_stateJson(lastViewedAt: '2025-01-06T09:15:00+00:00'));

      expect(state.lastViewedAt, DateTime.parse('2025-01-06T09:15:00+00:00'));
    });

    test('a valid previous_viewed_at parses into a real DateTime', () {
      final state = VaultLockModel.fromJson(
        _stateJson(lastViewedAt: '2025-01-07T09:15:00+00:00', previousViewedAt: '2025-01-06T09:15:00+00:00'),
      );

      expect(state.previousViewedAt, DateTime.parse('2025-01-06T09:15:00+00:00'));
    });

    test('does not decode a password or password_hash field even if present in the JSON', () {
      // Defense in depth: even if a future backend response accidentally
      // included one, this model has no field to carry it into.
      final json = {..._stateJson(), 'password_hash': r'$argon2id$v=19$...'};

      final state = VaultLockModel.fromJson(json);

      expect(state.toJson().containsKey('password_hash'), isFalse);
      expect(state.toJson().containsKey('password'), isFalse);
    });
  });

  group('VaultLockModel.toJson', () {
    test('round-trips configured/last_viewed_at/previous_viewed_at', () {
      final state = VaultLockModel.fromJson(
        _stateJson(lastViewedAt: '2025-01-07T09:15:00+00:00', previousViewedAt: '2025-01-06T09:15:00+00:00'),
      );

      final roundTripped = VaultLockModel.fromJson(state.toJson());

      expect(roundTripped.configured, state.configured);
      expect(roundTripped.lastViewedAt, state.lastViewedAt);
      expect(roundTripped.previousViewedAt, state.previousViewedAt);
    });

    test('serializes null timestamps back to null, not omitted', () {
      const state = VaultLockModel(configured: false);

      final json = state.toJson();

      expect(json['last_viewed_at'], isNull);
      expect(json['previous_viewed_at'], isNull);
    });
  });
}
