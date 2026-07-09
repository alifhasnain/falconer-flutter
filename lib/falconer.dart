/// Falconer — a Chucker-style HTTP inspector for the Dio client.
///
/// This is the public API surface. Platform-specific code lives behind
/// [Falconer] / `FalconerPlatform` in `lib/src/`.
library;

export 'src/config/falconer_config.dart' show FalconerConfig;
export 'src/config/retention_period.dart' show RetentionPeriod;
export 'src/falconer.dart' show Falconer;
export 'src/interceptor/falconer_interceptor.dart' show FalconerInterceptor;
