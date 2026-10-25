/// Diver refused a call. [message] is the server's own sentence, which says
/// what to fix: a key for another app, a campaign that has not been sent, a
/// token entry the server would not take.
class DiverPushException implements Exception {
  const DiverPushException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'DiverPushException($statusCode): $message';
}
