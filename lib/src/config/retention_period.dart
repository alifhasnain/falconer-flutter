/// How long captured transactions are kept before retention cleanup deletes
/// them.
///
/// [key] is the wire value sent to the native side, mirrored by Kotlin
/// `RetentionPeriod.fromKey` and Swift `RetentionWindow`. Adding a value here
/// means adding it to **both** mirrors — each maps an unknown key silently onto
/// its one-day window, so a one-sided addition would sweep at the wrong
/// interval with no error. `test/contract/contract_test.dart` pins the set.
///
/// Every window is bounded, and [oneMonth] is the ceiling. There is deliberately
/// no "keep forever": captured traffic is unredacted-by-default payload sitting
/// in an on-device SQLite file, so an unbounded window would let a debug build
/// accumulate request and response bodies indefinitely. Eventual deletion is a
/// property of the tool, not a setting the host app has to remember to choose.
///
/// Windows are rolling durations measured back from now, not calendar units:
/// [oneMonth] is a fixed 30 days.
enum RetentionPeriod {
  oneHour('oneHour'),
  oneDay('oneDay'),
  oneWeek('oneWeek'),

  /// The longest window available.
  oneMonth('oneMonth');

  const RetentionPeriod(this.key);

  /// The string sent across the channel.
  final String key;
}
