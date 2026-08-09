#if DEBUG
import Flutter
import Foundation

/// Parses the raw channel maps into the typed `RequestData` / `ResponseData` /
/// `ErrorData` models. Mirrors Kotlin `PayloadMapper`.
///
/// Number tolerance: Flutter's `StandardMessageCodec` delivers Dart ints as
/// `NSNumber`; by magnitude they may back an `Int`, `Int32` or `Int64`. Every
/// integer is coerced through `NSNumber`/`Int64` so the mapper never crashes on
/// the wire representation. Dart `null` arrives as `NSNull` and maps to `nil`.
/// `Uint8List` arrives as `FlutterStandardTypedData`.
enum PayloadMapper {

    // MARK: - Public entry points

    static func request(_ map: [String: Any]) -> RequestData? {
        guard let id = string(map[PayloadKeys.id]) else { return nil }
        return RequestData(
            id: id,
            startedAt: int64(map[PayloadKeys.startedAt]) ?? 0,
            method: string(map[PayloadKeys.method]) ?? "",
            url: string(map[PayloadKeys.url]) ?? "",
            host: string(map[PayloadKeys.host]) ?? "",
            path: string(map[PayloadKeys.path]) ?? "",
            scheme: string(map[PayloadKeys.scheme]) ?? "",
            requestHeaders: stringMap(map[PayloadKeys.requestHeaders]),
            requestContentType: string(map[PayloadKeys.requestContentType]),
            requestContentLength: int64(map[PayloadKeys.requestContentLength]),
            requestBody: string(map[PayloadKeys.requestBody]),
            requestBodyKind: string(map[PayloadKeys.requestBodyKind]) ?? BodyKinds.none
        )
    }

    static func response(_ map: [String: Any]) -> ResponseData? {
        guard let id = string(map[PayloadKeys.id]) else { return nil }
        return ResponseData(
            id: id,
            completedAt: int64(map[PayloadKeys.completedAt]) ?? 0,
            tookMs: int64(map[PayloadKeys.tookMs]) ?? 0,
            statusCode: int(map[PayloadKeys.statusCode]),
            statusMessage: string(map[PayloadKeys.statusMessage]),
            protocolName: string(map[PayloadKeys.protocolName]),
            responseHeaders: stringMap(map[PayloadKeys.responseHeaders]),
            responseContentType: string(map[PayloadKeys.responseContentType]),
            responseContentLength: int64(map[PayloadKeys.responseContentLength]),
            responseBody: string(map[PayloadKeys.responseBody]),
            responseBodyKind: string(map[PayloadKeys.responseBodyKind]),
            responseImageBytes: data(map[PayloadKeys.responseImageBytes])
        )
    }

    static func error(_ map: [String: Any]) -> ErrorData? {
        guard let id = string(map[PayloadKeys.id]) else { return nil }
        return ErrorData(
            id: id,
            completedAt: int64(map[PayloadKeys.completedAt]) ?? 0,
            tookMs: int64(map[PayloadKeys.tookMs]) ?? 0,
            error: string(map[PayloadKeys.error]) ?? ""
        )
    }

    // MARK: - Tolerant coercion helpers

    /// `NSNull`/absent -> nil; otherwise the value unwrapped.
    static func present(_ value: Any?) -> Any? {
        guard let value = value, !(value is NSNull) else { return nil }
        return value
    }

    static func string(_ value: Any?) -> String? {
        guard let value = present(value) else { return nil }
        if let s = value as? String { return s }
        return String(describing: value)
    }

    static func int64(_ value: Any?) -> Int64? {
        guard let value = present(value) else { return nil }
        if let n = value as? NSNumber { return n.int64Value }
        if let i = value as? Int { return Int64(i) }
        if let i = value as? Int64 { return i }
        if let i = value as? Int32 { return Int64(i) }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let v = int64(value) else { return nil }
        return Int(truncatingIfNeeded: v)
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let raw = present(value) as? [AnyHashable: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, val) in raw {
            let k = (key as? String) ?? String(describing: key)
            out[k] = (val as? String) ?? String(describing: val)
        }
        return out
    }

    static func data(_ value: Any?) -> Data? {
        guard let value = present(value) else { return nil }
        if let typed = value as? FlutterStandardTypedData { return typed.data }
        if let data = value as? Data { return data }
        if let bytes = value as? [UInt8] { return Data(bytes) }
        return nil
    }
}
#endif
