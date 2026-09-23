import 'package:flutter_cloud_sync/src/core/exceptions.dart';
import 'package:flutter_cloud_sync/src/providers/sync_push_ack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts only a complete push receipt', () {
    expect(
      () => verifySyncPushAcknowledgement({'accepted': 2, 'rejected': 0}, 2),
      returnsNormally,
    );
  });

  test('partial conflict receipt preserves pending changes', () {
    expect(
      () => verifySyncPushAcknowledgement({'accepted': 1, 'rejected': 1}, 2),
      throwsA(isA<CloudStorageException>()),
    );
  });

  test('missing or incomplete receipt is not acknowledged', () {
    for (final response in [
      <String, dynamic>{},
      {'accepted': 1, 'rejected': 0}
    ]) {
      expect(
        () => verifySyncPushAcknowledgement(response, 2),
        throwsA(isA<CloudStorageException>()),
      );
    }
  });
}
