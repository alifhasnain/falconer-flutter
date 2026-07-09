import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_falconer.dart';

/// The platform interface every Falconer backend implements.
///
/// This is the single seam an iOS implementation would target. Signatures use
/// only `Map`/primitive types — **no Android (or platform) types leak here** —
/// so the contract stays platform-agnostic. (D1-B in `doc/PLAN.md`.)
abstract class FalconerPlatform extends PlatformInterface {
  /// Constructs a FalconerPlatform.
  FalconerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FalconerPlatform _instance = MethodChannelFalconer();

  /// The default instance of [FalconerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFalconer].
  static FalconerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FalconerPlatform] when they
  /// register themselves.
  static set instance(FalconerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Round-trips the channel; returns `"pong"`. Diagnostic only.
  Future<String?> ping() {
    throw UnimplementedError('ping() has not been implemented.');
  }

  /// Forwards the resolved configuration map to the native side.
  Future<void> configure(Map<String, dynamic> config) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  /// Records a request as it is sent (two-phase logging, D4).
  Future<void> logRequest(Map<String, dynamic> data) {
    throw UnimplementedError('logRequest() has not been implemented.');
  }

  /// Records a completed response, merged onto the matching request by id.
  Future<void> logResponse(Map<String, dynamic> data) {
    throw UnimplementedError('logResponse() has not been implemented.');
  }

  /// Records a failed request, merged onto the matching request by id.
  Future<void> logError(Map<String, dynamic> data) {
    throw UnimplementedError('logError() has not been implemented.');
  }

  /// Clears all captured transactions.
  Future<void> clearTransactions() {
    throw UnimplementedError('clearTransactions() has not been implemented.');
  }

  /// Launches the native inspection UI.
  Future<void> launchUi() {
    throw UnimplementedError('launchUi() has not been implemented.');
  }

  /// Requests the runtime notification permission (Android 13+). Returns the
  /// grant result; pre-33 / no-Activity hosts resolve per the native contract.
  Future<bool> requestNotificationPermission() {
    throw UnimplementedError(
      'requestNotificationPermission() has not been implemented.',
    );
  }

  /// Live count of captured transactions. Defined now (EventChannel) to keep
  /// the contract stable for iOS, even though Android consumers are optional.
  Stream<int> get transactionCount {
    throw UnimplementedError('transactionCount has not been implemented.');
  }
}
