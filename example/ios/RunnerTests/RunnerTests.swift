import UIKit
import XCTest
@testable import falconer

/// iOS-side tests for the Falconer plugin.
///
/// - `ContractTests` mirror `test/contract/contract_test.dart` — they fail if the
///   Swift channel constants drift from the frozen Dart contract.
/// - The rest cover the debug-only engine internals (mapper / config / redaction
///   / DAO / formatting / export). All run headless on the simulator; the DAO
///   test uses an in-memory SQLite DB (no device storage).
final class ContractTests: XCTestCase {
    func testChannels() {
        XCTAssertEqual(FalconerChannels.method, "falconer")
        XCTAssertEqual(FalconerChannels.transactionCountEvent, "falconer/transactionCount")
    }

    func testMethodNames() {
        let names: Set<String> = [
            FalconerMethods.ping, FalconerMethods.configure,
            FalconerMethods.logRequest, FalconerMethods.logResponse,
            FalconerMethods.logError, FalconerMethods.clearTransactions,
            FalconerMethods.launchUi, FalconerMethods.requestNotificationPermission,
        ]
        XCTAssertEqual(names, [
            "ping", "configure", "logRequest", "logResponse", "logError",
            "clearTransactions", "launchUi", "requestNotificationPermission",
        ])
    }

    func testPayloadKeys() {
        XCTAssertEqual(PayloadKeys.id, "id")
        XCTAssertEqual(PayloadKeys.startedAt, "startedAt")
        XCTAssertEqual(PayloadKeys.method, "method")
        XCTAssertEqual(PayloadKeys.url, "url")
        XCTAssertEqual(PayloadKeys.host, "host")
        XCTAssertEqual(PayloadKeys.path, "path")
        XCTAssertEqual(PayloadKeys.scheme, "scheme")
        XCTAssertEqual(PayloadKeys.requestHeaders, "requestHeaders")
        XCTAssertEqual(PayloadKeys.requestContentType, "requestContentType")
        XCTAssertEqual(PayloadKeys.requestContentLength, "requestContentLength")
        XCTAssertEqual(PayloadKeys.requestBody, "requestBody")
        XCTAssertEqual(PayloadKeys.requestBodyKind, "requestBodyKind")
        XCTAssertEqual(PayloadKeys.completedAt, "completedAt")
        XCTAssertEqual(PayloadKeys.tookMs, "tookMs")
        XCTAssertEqual(PayloadKeys.statusCode, "statusCode")
        XCTAssertEqual(PayloadKeys.statusMessage, "statusMessage")
        XCTAssertEqual(PayloadKeys.protocolName, "protocol")
        XCTAssertEqual(PayloadKeys.responseHeaders, "responseHeaders")
        XCTAssertEqual(PayloadKeys.responseContentType, "responseContentType")
        XCTAssertEqual(PayloadKeys.responseContentLength, "responseContentLength")
        XCTAssertEqual(PayloadKeys.responseBody, "responseBody")
        XCTAssertEqual(PayloadKeys.responseBodyKind, "responseBodyKind")
        XCTAssertEqual(PayloadKeys.responseImageBytes, "responseImageBytes")
        XCTAssertEqual(PayloadKeys.error, "error")
    }

    func testConfigKeys() {
        XCTAssertEqual(
            Set([ConfigKeys.enabled, ConfigKeys.maxContentLength,
                 ConfigKeys.redactHeaders, ConfigKeys.retention, ConfigKeys.showNotification]),
            ["enabled", "maxContentLength", "redactHeaders", "retention", "showNotification"]
        )
    }

    func testBodyKinds() {
        XCTAssertEqual(
            Set([BodyKinds.none, BodyKinds.text, BodyKinds.json,
                 BodyKinds.multipart, BodyKinds.image, BodyKinds.unsupported]),
            ["none", "text", "json", "multipart", "image", "unsupported"]
        )
    }
}

final class PayloadMapperTests: XCTestCase {
    func testRequestWithNullsAndMixedNumbers() {
        let map: [String: Any] = [
            PayloadKeys.id: "1700000000000-0",
            PayloadKeys.startedAt: Int(1_700_000_000_000),
            PayloadKeys.method: "GET",
            PayloadKeys.url: "https://api.example.com/users?page=1",
            PayloadKeys.host: "api.example.com",
            PayloadKeys.path: "/users",
            PayloadKeys.scheme: "https",
            PayloadKeys.requestHeaders: ["accept": "application/json"],
            PayloadKeys.requestContentType: NSNull(),
            PayloadKeys.requestContentLength: NSNull(),
            PayloadKeys.requestBody: NSNull(),
            PayloadKeys.requestBodyKind: "none",
        ]
        let r = PayloadMapper.request(map)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.method, "GET")
        XCTAssertEqual(r?.startedAt, 1_700_000_000_000)
        XCTAssertEqual(r?.host, "api.example.com")
        XCTAssertNil(r?.requestContentType)
        XCTAssertNil(r?.requestBody)
        XCTAssertEqual(r?.requestHeaders["accept"], "application/json")
    }

    func testResponseIntTolerance() {
        let map: [String: Any] = [
            PayloadKeys.id: "x",
            PayloadKeys.completedAt: NSNumber(value: Int64(1_700_000_000_120)),
            PayloadKeys.tookMs: NSNumber(value: 120),
            PayloadKeys.statusCode: NSNumber(value: 200),
            PayloadKeys.responseBodyKind: "json",
        ]
        let r = PayloadMapper.response(map)
        XCTAssertEqual(r?.statusCode, 200)
        XCTAssertEqual(r?.tookMs, 120)
        XCTAssertEqual(r?.completedAt, 1_700_000_000_120)
    }

    func testMissingIdIsRejected() {
        XCTAssertNil(PayloadMapper.request([:]))
        XCTAssertNil(PayloadMapper.error([:]))
    }
}

final class ConfigAndRedactionTests: XCTestCase {
    func testConfigParse() {
        let c = FalconerNativeConfig.from([
            ConfigKeys.enabled: true,
            ConfigKeys.maxContentLength: 10,
            ConfigKeys.redactHeaders: ["Authorization", "X-Api-Key"],
            ConfigKeys.retention: "oneWeek",
            ConfigKeys.showNotification: false,
        ])
        XCTAssertTrue(c.enabled)
        XCTAssertEqual(c.maxContentLength, 10)
        XCTAssertTrue(c.redactHeaders.contains("authorization"))
        XCTAssertTrue(c.redactHeaders.contains("x-api-key"))
        XCTAssertEqual(c.retention, .oneWeek)
        XCTAssertFalse(c.showNotification)
    }

    func testRetentionWireKeysMatchTheDartEnum() {
        // `from(key:)` falls back to .oneDay on an unknown key, so a key Dart
        // sends but this enum lacks would sweep at the wrong window with no
        // error. Pin the whole set (mirrors test/contract/contract_test.dart).
        XCTAssertEqual(
            Set(["oneHour", "oneDay", "oneWeek", "oneMonth"]),
            Set(RetentionWindow.allCases.map { $0.rawValue })
        )
        XCTAssertEqual(RetentionWindow.from(key: "oneMonth"), .oneMonth)
        XCTAssertEqual(RetentionWindow.oneMonth.millis, 30 * 24 * 60 * 60 * 1000)
        XCTAssertEqual(RetentionWindow.from(key: "bogus"), .oneDay)
        // The retired "forever" key degrades to one day — deletes more, not less.
        XCTAssertEqual(RetentionWindow.from(key: "forever"), .oneDay)
        // One month is the ceiling: no window may retain longer.
        XCTAssertEqual(
            RetentionWindow.allCases.map { $0.millis }.max(),
            RetentionWindow.oneMonth.millis
        )
    }

    func testRedactionIsCaseInsensitive() {
        let out = Redactor.redact(
            headers: ["Authorization": "secret", "Accept": "json"],
            redactHeaders: ["authorization"]
        )
        XCTAssertEqual(out["Authorization"], "**redacted**")
        XCTAssertEqual(out["Accept"], "json")
    }

    func testTruncationMarker() {
        let body = String(repeating: "a", count: 20)
        let out = Redactor.truncate(body: body, size: 20, maxContentLength: 5)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.hasPrefix("aaaaa"))
        XCTAssertTrue(out!.contains("[Falconer: truncated — original 20 bytes, showing first 5]"))
    }

    func testUnderCapNotTruncated() {
        XCTAssertEqual(Redactor.truncate(body: "abc", size: 3, maxContentLength: 5), "abc")
    }
}

final class DaoTests: XCTestCase {
    private func makeTx(id: String, method: String = "GET") -> HttpTransaction {
        HttpTransaction(
            id: id, startedAt: 1_700_000_000_000, method: method,
            url: "https://api.example.com/users", host: "api.example.com",
            path: "/users", scheme: "https", requestHeaders: ["accept": "application/json"],
            requestContentType: nil, requestContentLength: nil, requestBody: nil,
            requestBodyKind: BodyKinds.none, completedAt: nil, tookMs: nil, statusCode: nil,
            statusMessage: nil, protocolName: nil, responseHeaders: [:], responseContentType: nil,
            responseContentLength: nil, responseBody: nil, responseBodyKind: nil,
            responseImageBytes: nil, error: nil
        )
    }

    func testInsertQueryClear() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let dao = try HttpTransactionDao(db: db)
        XCTAssertEqual(try dao.count(), 0)

        try dao.upsert(makeTx(id: "a"))
        try dao.upsert(makeTx(id: "b", method: "POST"))
        XCTAssertEqual(try dao.count(), 2)

        let fetched = try dao.byId("a")
        XCTAssertEqual(fetched?.method, "GET")
        XCTAssertEqual(fetched?.requestHeaders["accept"], "application/json")

        XCTAssertEqual(try dao.listRowsFiltered("POST").count, 1)
        XCTAssertEqual(try dao.listRowsFiltered("api.example.com").count, 2)
        XCTAssertEqual(try dao.listRows().count, 2)

        // The list projection carries the columns the list renders and stops
        // there — bodies and the image BLOB are absent by construction.
        let row = try XCTUnwrap(try dao.listRows().first { $0.id == "a" })
        XCTAssertEqual(row.method, "GET")
        XCTAssertEqual(row.path, "/users")
        XCTAssertEqual(row.host, "api.example.com")

        try dao.clear()
        XCTAssertEqual(try dao.count(), 0)
    }

    func testUpsertMergesById() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let dao = try HttpTransactionDao(db: db)
        var tx = makeTx(id: "same")
        try dao.upsert(tx)
        tx.statusCode = 200
        tx.completedAt = 1_700_000_000_120
        try dao.upsert(tx)
        XCTAssertEqual(try dao.count(), 1)
        XCTAssertEqual(try dao.byId("same")?.statusCode, 200)
    }
}

final class FormattingAndExportTests: XCTestCase {
    func testMatchRanges() {
        XCTAssertEqual(BodyFormatting.matchRanges(in: "aXaXa", query: "x").count, 2)
        XCTAssertEqual(BodyFormatting.matchRanges(in: "abc", query: "").count, 0)
    }

    func testPrettyJSON() {
        XCTAssertNotNil(BodyFormatting.prettyJSON("{\"a\":1}"))
        XCTAssertNil(BodyFormatting.prettyJSON("definitely not json {"))
    }

    func testFormatBytes() {
        XCTAssertEqual(BodyFormatting.formatBytes(512), "512 B")
        XCTAssertEqual(BodyFormatting.formatBytes(nil), "—")
    }

    func testCurlBuilderRedactedHeaderTravels() {
        let tx = HttpTransaction(
            id: "c", startedAt: 0, method: "POST",
            url: "https://api.example.com/pay", host: "api.example.com", path: "/pay",
            scheme: "https", requestHeaders: ["Authorization": "**redacted**"],
            requestContentType: "application/json", requestContentLength: 9,
            requestBody: "{\"a\":1}", requestBodyKind: BodyKinds.json,
            completedAt: nil, tookMs: nil, statusCode: nil, statusMessage: nil,
            protocolName: nil, responseHeaders: [:], responseContentType: nil,
            responseContentLength: nil, responseBody: nil, responseBodyKind: nil,
            responseImageBytes: nil, error: nil
        )
        let curl = CurlBuilder.build(tx)
        XCTAssertTrue(curl.contains("curl -X POST 'https://api.example.com/pay'"))
        XCTAssertTrue(curl.contains("**redacted**"))
        XCTAssertTrue(curl.contains("--data '{\"a\":1}'"))
    }
}

final class ShakeDetectorTests: XCTestCase {
    /// Regression: the swizzle must stay scoped to UIWindow. A non-UIWindow
    /// responder receiving a shake once crashed with "unrecognized selector
    /// falconer_motionEnded:". This must not crash.
    func testMotionOnNonWindowResponderDoesNotCrash() {
        ShakeDetector.install()
        UIView().motionEnded(.motionShake, with: nil)
        UIViewController().motionEnded(.motionShake, with: nil)
    }

    /// A shake reaching a UIWindow posts `.falconerShake` AND forwards up the
    /// responder chain without crashing. Attaching the window to the host's
    /// UIWindowScene exercises the exact path that once crashed with
    /// "-[UIWindowScene falconer_motionEnded:with:]: unrecognized selector".
    func testWindowShakePostsNotificationAndForwardsCleanly() {
        ShakeDetector.install()
        var posted = false
        let token = NotificationCenter.default.addObserver(
            forName: .falconerShake, object: nil, queue: nil
        ) { _ in posted = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.motionEnded(.motionShake, with: nil)  // forwards to UIWindowScene
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(posted, "shake on a UIWindow did not post .falconerShake")
    }
}
