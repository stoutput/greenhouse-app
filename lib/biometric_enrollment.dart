import 'package:flutter/services.dart';

/// The platform keeps an enrollment-bound sentinel, without reading biometric
/// data or prompting. Only password authentication may establish a new baseline.
class BiometricEnrollment {
  static const _channel = MethodChannel('app.greenhouse/biometric_enrollment');

  Future<void> reset({required bool enrolled}) =>
      _channel.invokeMethod<void>('reset', {'enrolled': enrolled});

  Future<bool> hasChanged({required bool enrolled}) async =>
      await _channel.invokeMethod<bool>('hasChanged', {'enrolled': enrolled}) ??
      true;
}
