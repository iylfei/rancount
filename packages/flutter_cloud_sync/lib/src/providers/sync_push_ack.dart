import '../core/exceptions.dart';

/// Only acknowledge a local batch after the server confirms every change.
/// A partial 200 response must leave the entire batch pending for replay.
void verifySyncPushAcknowledgement(
  Map<String, dynamic> response,
  int requestedCount,
) {
  final accepted = response['accepted'];
  final rejected = response['rejected'];
  if (accepted is! int ||
      rejected is! int ||
      accepted != requestedCount ||
      rejected != 0) {
    if (rejected is int && rejected > 0) {
      throw CloudStorageException(
        '云端拒绝了 $rejected 条同步变更，本机修改仍保留。请检查云同步状态。',
      );
    }
    throw CloudStorageException('云端同步回执不完整，本机修改仍保留。请稍后重试。');
  }
}
