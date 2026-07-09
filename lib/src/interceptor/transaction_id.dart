/// Generates transaction ids that are unique within a single app session.
///
/// Format: `<sessionEpochMs>-<monotonicCounter>` (D3). The session epoch is
/// captured once at first use; the counter increments per id. This decouples
/// request/response correlation from wall-clock collisions and needs no
/// platform support, so it is reused verbatim by iOS.
class TransactionId {
  TransactionId._();

  static final int _sessionEpoch = DateTime.now().millisecondsSinceEpoch;
  static int _counter = 0;

  /// Returns the next unique id for this session.
  static String next() => '$_sessionEpoch-${_counter++}';
}
