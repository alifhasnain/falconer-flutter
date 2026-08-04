// Internal runtime state shared across all FalconerInterceptor instances.
//
// `Falconer.configure` calls applyConfig, which caches the resolved enabled
// flag and the active config (redaction set + content cap) read on the
// interceptor hot path.
import 'config/falconer_config.dart';

/// When `false`, the interceptor reads no bodies and sends no channel calls.
/// Initialized from the default config so a release build is inert before
/// `configure` is even called — and, since `resolveEnabled` is `false` for every
/// release build, it stays inert no matter what `configure` is passed.
bool captureEnabled = const FalconerConfig().effectiveEnabled;

/// The active configuration the interceptor reads when building payloads.
FalconerConfig activeConfig = const FalconerConfig();

/// Applies [config]: caches the enabled flag and the active config.
void applyConfig(FalconerConfig config) {
  activeConfig = config;
  captureEnabled = config.effectiveEnabled;
}
