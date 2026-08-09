#
# Falconer — Chucker-style HTTP inspector for the Dio client.
#
# iOS distribution note (Method A, mirrors Android's release stripping):
# the entire inspector (RealFalconerEngine, SwiftUI UI, SQLite storage, capture)
# lives behind `#if DEBUG`. `flutter build ipa --release` compiles this pod with
# the Release configuration, where `DEBUG` is NOT defined, so the inspector
# source is never compiled and is physically absent from the release IPA. Only
# `NoOpFalconerEngine` (inert) and the thin channel wiring survive.
#
# Storage uses the system `libsqlite3` (already on every device) — there is NO
# third-party dependency to leak into a release build.
#
Pod::Spec.new do |s|
  s.name             = 'falconer'
  s.version          = '0.3.0'
  s.summary          = 'A Chucker-style HTTP inspector for the Dio client.'
  s.description      = <<-DESC
Capture, inspect, search and export Dio HTTP traffic in a native on-device UI.
The inspector is stripped from release builds (Method A: `#if DEBUG`).
                       DESC
  s.homepage         = 'https://github.com/alifhasnain/falconer-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'alifhasnain' => 'alif.hasnain@sslwireless.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # The inspector persists captured traffic in the system SQLite. Every call
  # site into it is compiled only under `#if DEBUG`, so libsqlite3 is linked in
  # the Debug configuration ONLY (see OTHER_LDFLAGS below) — a release build
  # links nothing beyond what Flutter/Swift already pull in, which is the
  # cleanest posture for a PCI audit.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Make the `#if DEBUG` stripping explicit rather than riding on CocoaPods'
    # defaults: DEBUG is defined ONLY for the Debug configuration, so Release and
    # Profile builds strip the inspector. `$(inherited)` keeps any other flags.
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]' => '$(inherited) DEBUG',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Profile]' => '$(inherited)',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Release]' => '$(inherited)',
    # Link the system SQLite only where the storage code actually exists.
    'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -lsqlite3',
  }
  s.swift_version = '5.0'
end
