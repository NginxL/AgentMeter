import Foundation
import MeterCore
import MeterProviders

// Synthetic known-answer vectors generated with Node's standard crypto module from the
// documented-in-source envelope layout. They contain only fixture-user / fixture-token.
let personalFixture = "dGMFEAAAAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh/549SVAMV06gbwCdSqqtsyx+Tb4BUfBncJn/kNAEsh0kitZpJoWBeg1GMVpRvKczbVn9g+neqYDTlkeWPhuQcFxx7cVGXugXNdwXXRGdBFPvU1pWWulJbLH81uRUY3pbVbTnsV1JkWdRfk4bT9duOCYDzql9PkEoydV6q7+Z9onZg4IGEGuXzbNEs26x9ghNKzak30uJSRJzwDFDRlHUMz"
let internalFixture = "dGMFEAAAAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh+dty8oN92a1YS3seINY5c/Nya/wfvencoE+c/uyBghZVlRJ3Ss9+2/qp7ixBtEmpHTmCiZTA8pr3mlx/bPBf62/Jm7Pv81LWkAsJpw8s9rY4YwvavPYzrYN+3jloCDWmo+YhvHGOBCnAq12aSL/pAeeXBNaNs1S85IdoKBC4Q77Z5olQp4Haz2dCT7aEtrTCiNoqtJrN6PYF0cy8pR0O/n"
let enterpriseFixture = "dGMFEAAAAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh+F/9PTFA7koBaBM9Dv0xtF+qT05vvgDI9NpZmsHIT3S9id+6NVXkiTrJWSZHJvI26WkauNkAE1aEH2ZsDvY33nqqsRFK3ZWiLKLx+2TsQ+c11duogEprXujaMgvhIQ2o2idGhXnrCJ+15u8kKFMK00y87rqMTbhpvgMRjP1aPt4TW6qvQZ2JT08iTnle4BmQw="
let validUsage = Data(#"{"code":0,"is_credits_billing":true,"user_entitlement_pack_list":[{"entitlement_base_info":{"quota":{"credits_limit":4000},"end_time":1800000000},"usage":{"credits_amount":1000}},{"entitlement_base_info":{"product_extra":{"subscription_extra":{"quota":{"credits_limit":200}}}},"usage":{"credits_amount":100}},{"entitlement_base_info":{"quota":{"credits_limit":-1}},"usage":{"credits_amount":100}}]}"#.utf8)

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw Failure(description: message) }
}

actor TestTransport {
    var calls = 0
    let body: Data
    let status: Int
    init(body: Data = validUsage, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) throws -> (Data, Int) {
        calls += 1
        try expect(request.url?.absoluteString == "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage", "Unexpected endpoint")
        try expect(request.httpMethod == "POST", "Usage requires a read-only POST query")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Cloud-IDE-JWT fixture-token", "Incorrect native credential format")
        let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        try expect(payload?["require_usage"] as? Bool == true && payload?["req_source"] as? Int == 2 && payload?.count == 2, "Unexpected usage query")
        return (body, status)
    }
}

func run() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AgentMeter-TraeChecks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("storage.json")
    func write(_ envelope: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["iCubeAuthInfo://icube.cloudide": envelope, "unrelated": "not-read-by-provider"])
        try data.write(to: storage)
    }
    var count = 0
    try write(personalFixture)
    let before = try Data(contentsOf: storage)
    let success = TestTransport()
    let snapshot = try await TraeProvider(storageURL: storage, transport: { try await success.send($0) }).fetch()
    try expect(snapshot.provider == .trae && snapshot.windows.map(\.usedPercent) == [25, 50, nil], "Native credential or quota parsing failed")
    try expect(snapshot.windows.allSatisfy { $0.resetsAt == nil }, "Pack expiry must not become quota reset or billing date")
    try expect(snapshot.accountID == nil && snapshot.plan == nil, "Do not infer plan or publish account identity")
    let after = try Data(contentsOf: storage)
    try expect(before == after, "Native credentials were changed")
    count += 1
    print("PASS native known-answer decryption and personal usage request; file unchanged")

    var unknownHeader = Data(base64Encoded: personalFixture)!
    unknownHeader[0] = 0
    var corrupted = Data(base64Encoded: personalFixture)!
    corrupted[40] ^= 1
    for (label, envelope) in [("internal account", internalFixture), ("enterprise account", enterpriseFixture),
                              ("unknown envelope", unknownHeader.base64EncodedString()),
                              ("corrupt envelope", corrupted.base64EncodedString()), ("invalid base64", "not-base64")] {
        try write(envelope)
        let capture = TestTransport()
        var thrown: Error?
        do { _ = try await TraeProvider(storageURL: storage, transport: { try await capture.send($0) }).fetch() }
        catch { thrown = error }
        try expect(thrown != nil, "Unsupported credentials were accepted")
        if label == "internal account" || label == "enterprise account" {
            guard let failure = thrown as? MeterFailure, case .unsupportedAccount = failure else {
                throw Failure(description: "Unsupported account needs a distinct failure")
            }
        }
        let calls = await capture.calls
        try expect(calls == 0, "Unsupported credentials reached a network transport")
        try expect(!(thrown?.localizedDescription.contains("fixture-token") ?? false) && !(thrown?.localizedDescription.contains("fixture-user") ?? false), "Credential data appeared in an error")
        count += 1
        print("PASS \(label) rejected before transport")
    }

    try Data("{}".utf8).write(to: storage)
    let absent = TestTransport()
    do {
        _ = try await TraeProvider(storageURL: storage, transport: { try await absent.send($0) }).fetch()
        throw Failure(description: "Missing native login accepted")
    } catch MeterFailure.notSignedIn { }
    let absentCalls = await absent.calls
    try expect(absentCalls == 0, "Missing native login used transport")
    count += 1
    print("PASS missing login does not use another profile or Keychain")

    try write(personalFixture)
    for status in [401, 403, 429, 503] {
        let capture = TestTransport(body: Data("fixture-token must not appear in errors".utf8), status: status)
        var failure: MeterFailure?
        do { _ = try await TraeProvider(storageURL: storage, transport: { try await capture.send($0) }).fetch() }
        catch let error as MeterFailure { failure = error }
        guard let failure else { throw Failure(description: "HTTP error did not fail") }
        switch status {
        case 401: guard case .expired = failure else { throw Failure(description: "Wrong expired classification") }
        case 429: guard case .rateLimited = failure else { throw Failure(description: "Wrong limit classification") }
        default: guard case .unavailable = failure else { throw Failure(description: "Wrong HTTP error classification") }
        }
        try expect(!failure.localizedDescription.contains("fixture-token"), "HTTP body appeared in an error")
        count += 1
        print("PASS sanitized HTTP \(status)")
    }

    let missingValues = Data(#"{"user_entitlement_pack_list":[{"entitlement_base_info":{"quota":{"credits_limit":100}},"usage":{}},{"entitlement_base_info":{"quota":{"credits_limit":0}},"usage":{"credits_amount":0}},{"entitlement_base_info":{"quota":{"credits_limit":true}},"usage":{"credits_amount":1}},{"entitlement_base_info":{"quota":{"credits_limit":100}},"usage":{"credits_amount":null}}]}"#.utf8)
    let unknown = try TraeQuotaParser.parse(missingValues)
    try expect(unknown.windows.count == 4 && unknown.windows.allSatisfy { $0.usedPercent == nil }, "Unknown quantities must not become zero usage")
    count += 1
    print("PASS missing, zero, boolean, and null quota amounts remain unavailable")

    for payload in ["{}", "{", #"{"code":7,"message":"fixture-token"}"#, #"{"user_entitlement_pack_list":[]}"#] {
        var failed = false
        do { _ = try TraeQuotaParser.parse(Data(payload.utf8)) }
        catch { failed = true; try expect(!error.localizedDescription.contains("fixture-token"), "Raw business error leaked") }
        try expect(failed, "Malformed or unavailable quota accepted")
        count += 1
    }
    print("\(count) TRAE checks, 0 failures; synthetic credentials and transport only")
}

Task {
    do { try await run(); exit(0) }
    catch { print("FAIL: \(error)"); exit(1) }
}
dispatchMain()
