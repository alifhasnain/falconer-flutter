/// How long captured transactions are kept before retention cleanup deletes
/// them (D6). [key] is the wire value sent to the native side, mirrored by the
/// Kotlin `RetentionPeriod.fromKey`.
enum RetentionPeriod {
  oneHour('oneHour'),
  oneDay('oneDay'),
  oneWeek('oneWeek'),
  forever('forever');

  const RetentionPeriod(this.key);

  /// The string sent across the channel.
  final String key;
}
