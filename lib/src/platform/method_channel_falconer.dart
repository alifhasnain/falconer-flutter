import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'contract.dart';
import 'falconer_platform.dart';

/// An implementation of [FalconerPlatform] that uses platform channels.
///
/// Method and channel names come from [FalconerMethods] / [FalconerChannels]
/// (the frozen contract), mirrored in `android/.../channel/MethodNames.kt`.
class MethodChannelFalconer extends FalconerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    FalconerChannels.method,
  );

  /// The event channel carrying the live transaction count.
  @visibleForTesting
  final EventChannel transactionCountChannel = const EventChannel(
    FalconerChannels.transactionCountEvent,
  );

  @override
  Future<String?> ping() {
    return methodChannel.invokeMethod<String>(FalconerMethods.ping);
  }

  @override
  Future<void> configure(Map<String, dynamic> config) {
    return methodChannel.invokeMethod<void>(FalconerMethods.configure, config);
  }

  @override
  Future<void> logRequest(Map<String, dynamic> data) {
    return methodChannel.invokeMethod<void>(FalconerMethods.logRequest, data);
  }

  @override
  Future<void> logResponse(Map<String, dynamic> data) {
    return methodChannel.invokeMethod<void>(FalconerMethods.logResponse, data);
  }

  @override
  Future<void> logError(Map<String, dynamic> data) {
    return methodChannel.invokeMethod<void>(FalconerMethods.logError, data);
  }

  @override
  Future<void> clearTransactions() {
    return methodChannel.invokeMethod<void>(FalconerMethods.clearTransactions);
  }

  @override
  Future<void> launchUi() {
    return methodChannel.invokeMethod<void>(FalconerMethods.launchUi);
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final granted = await methodChannel.invokeMethod<bool>(
      FalconerMethods.requestNotificationPermission,
    );
    return granted ?? false;
  }

  @override
  Stream<int> get transactionCount => transactionCountChannel
      .receiveBroadcastStream()
      .map((event) => event as int);
}
