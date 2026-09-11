/// Falconer — a Chucker-style HTTP inspector for the Dio client.
///
/// This is the public API surface. Platform-specific code lives behind
/// [Falconer] / `FalconerPlatform` in `lib/src/`.
library;

export 'src/capture/body_codec.dart' show BodyKind;
export 'src/capture/body_decoder.dart'
    show FalconerBodyContext, FalconerBodyDecoder, FalconerDirection;
export 'src/capture/falconer_extras.dart' show FalconerExtras;
export 'src/config/falconer_config.dart' show FalconerConfig;
export 'src/config/retention_period.dart' show RetentionPeriod;
export 'src/falconer.dart' show Falconer;
export 'src/interceptor/falconer_interceptor.dart' show FalconerInterceptor;
