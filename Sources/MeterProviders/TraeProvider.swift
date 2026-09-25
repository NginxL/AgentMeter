import Foundation
import CoreFoundation
import CryptoKit
import CommonCrypto
import MeterCore

/// Experimental compatibility with the personal TRAE SOLO CN client (observed in version 0.1.63).
/// This uses the client's internal usage endpoint, not TRAE Enterprise OpenAPI.
public struct TraeProvider: UsageProvider {
    public let kind: ProviderKind = .trae
    private let storageURL: URL
    private let transport: (@Sendable (URLRequest) async throws -> (Data, Int))?

    public init(storageURL: URL? = nil,
                transport: (@Sendable (URLRequest) async throws -> (Data, Int))? = nil) {
        self.storageURL = storageURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TRAE SOLO CN/User/globalStorage/storage.json")
        self.transport = transport
    }

    public func fetch() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let token = try await Task.detached(priority: .utility) {
            try TraeNativeCredential.readPersonalToken(at: storageURL)
        }.value
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Cloud-IDE-JWT \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentMeter/1.0.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(#"{"require_usage":true,"req_source":2}"#.utf8)
        do {
            let result: (Data, Int)
            if let transport { result = try await transport(request) }
            else { result = try await Self.requestUsage(request) }
            try Task.checkCancellation()
            switch result.1 {
            case 200: return try TraeQuotaParser.parse(result.0)
            case 401: throw MeterFailure.expired("TRAE SOLO CN")
            case 403: throw MeterFailure.unavailable("TRAE SOLO CN 拒绝读取额度，请检查当前个人账号权限。")
            case 429: throw MeterFailure.rateLimited
            default: throw MeterFailure.unavailable("TRAE SOLO CN 额度接口暂不可用（HTTP \(result.1)）。")
            }
        } catch is CancellationError { throw CancellationError() }
        catch let failure as MeterFailure { throw failure }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError where error.code == .timedOut { throw MeterFailure.timedOut }
        catch { throw MeterFailure.unavailable("无法读取 TRAE SOLO CN 额度，请检查网络与官方客户端登录状态。") }
    }

    private static func requestUsage(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: TraeNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MeterFailure.invalidResponse("TRAE SOLO CN 返回了无效响应。")
        }
        return (data, response.statusCode)
    }
}

/// Quota packs may have independent expiration dates. An expiration is not a recurring reset,
/// so this adapter deliberately does not map end_time to QuotaWindow.resetsAt.
public enum TraeQuotaParser {
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard data.count <= 1_048_576,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MeterFailure.invalidResponse("TRAE SOLO CN 返回了无法解析的额度数据。")
        }
        if let code = root["code"], (numeric(code) ?? -1) != 0 {
            throw MeterFailure.unavailable("TRAE SOLO CN 未能读取额度，请在官方客户端检查登录状态。")
        }
        guard let packs = root["user_entitlement_pack_list"] as? [[String: Any]], !packs.isEmpty else {
            throw MeterFailure.invalidResponse("TRAE SOLO CN 未返回可用的个人积分额度。")
        }
        var windows: [QuotaWindow] = []
        for (index, pack) in packs.enumerated() {
            guard let base = pack["entitlement_base_info"] as? [String: Any] else { continue }
            let extra = base["product_extra"] as? [String: Any]
            let subscription = extra?["subscription_extra"] as? [String: Any]
            guard let quota = (base["quota"] as? [String: Any]) ?? (subscription?["quota"] as? [String: Any]),
                  quota.keys.contains("credits_limit") else { continue }
            let limit = numeric(quota["credits_limit"])
            let usage = pack["usage"] as? [String: Any]
            let used = numeric(usage?["credits_amount"])
            var percent: Double?
            if let limit, limit > 0, let used, used >= 0 { percent = used / limit * 100 }
            // Unlimited, zero, and missing limits cannot produce a finite remaining percentage.
            let suffix = limit == -1 ? " · 无限额" : ""
            windows.append(QuotaWindow(id: "trae.credits.\(index)", title: "积分包 \(index + 1)\(suffix)", usedPercent: percent))
        }
        guard !windows.isEmpty else { throw MeterFailure.invalidResponse("TRAE SOLO CN 未返回可识别的积分额度。") }
        return UsageSnapshot(provider: .trae, windows: windows, fetchedAt: fetchedAt,
                             source: "TRAE SOLO CN · Experimental")
    }

    private static func numeric(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

private final class TraeNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum TraeNativeCredential {
    private static let storageKey = "iCubeAuthInfo://icube.cloudide"

    static func readPersonalToken(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { throw MeterFailure.notSignedIn("TRAE SOLO CN") }
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8_388_608 else { throw invalidStorage() }
            data = try Data(contentsOf: url)
        } catch let error as MeterFailure { throw error }
        catch { throw MeterFailure.unavailable("无法读取 TRAE SOLO CN 的本机登录信息。") }
        guard let storage = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let encoded = storage[storageKey] as? String else { throw MeterFailure.notSignedIn("TRAE SOLO CN") }
        let clear = try decryptEnvelope(encoded)
        guard let credential = (try? JSONSerialization.jsonObject(with: clear)) as? [String: Any],
              let account = credential["account"] as? [String: Any],
              let scope = account["scope"] as? String else { throw invalidStorage() }
        // Enterprise/internal accounts use different authentication and routing. Never send their
        // credentials to the personal service merely because this app is installed in China.
        guard scope == "marscode" else {
            throw MeterFailure.unsupportedAccount("TRAE SOLO CN")
        }
        guard let token = credential["token"] as? String, !token.isEmpty, token.utf8.count <= 32_768,
              token.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
            throw MeterFailure.notSignedIn("TRAE SOLO CN")
        }
        return token
    }

    /// Independent implementation of the installed client's native envelope format.
    /// The format constant below is public application data, not a user key or credential.
    /// An unknown header or failed integrity check fails closed; no vendor code is evaluated.
    private static func decryptEnvelope(_ encoded: String) throws -> Data {
        guard encoded.utf8.count <= 1_048_576, let bytes = Data(base64Encoded: encoded),
              bytes.count > 38, bytes.prefix(6) == Data([116, 99, 5, 16, 0, 0]),
              (bytes.count - 38).isMultiple(of: 16) else { throw invalidStorage() }
        let formatSalt = Data([77, 212, 194, 230, 184, 49, 98, 9, 14, 82, 179, 199, 166, 115, 59, 164,
                               28, 178, 70, 43, 130, 154, 181, 138, 25, 107, 57, 219, 87, 23, 117, 36,
                               244, 155, 175, 127, 8, 232, 214, 141, 38, 167, 46, 55, 193, 169, 90, 47,
                               31, 5, 165, 24, 146, 174, 242, 148, 151, 50, 182, 42, 56, 170, 221, 88])
        let seed = bytes.subdata(in: 6..<38)
        var material = Data(SHA512.hash(data: seed))
        material.append(formatSalt)
        let derived = Data(SHA512.hash(data: material))
        let key = derived.subdata(in: 0..<16)
        let iv = derived.subdata(in: 16..<32)
        let cipher = bytes.subdata(in: 38..<bytes.count)
        var plain = Data(count: cipher.count + kCCBlockSizeAES128)
        var count = 0
        let capacity = plain.count
        let status = plain.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    cipher.withUnsafeBytes { cipherBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                cipherBytes.baseAddress, cipher.count, output.baseAddress, capacity, &count)
                    }
                }
            }
        }
        guard status == kCCSuccess, count > 64 else { throw invalidStorage() }
        plain.count = count
        let payload = plain.subdata(in: 64..<count)
        let expected = Data(SHA512.hash(data: payload))
        var difference: UInt8 = 0
        for index in 0..<64 { difference |= plain[index] ^ expected[index] }
        guard difference == 0 else { throw invalidStorage() }
        return payload
    }

    private static func invalidStorage() -> MeterFailure {
        .unavailable("TRAE SOLO CN 本机登录格式尚不支持或已损坏，请更新 AgentMeter，或使用手动额度。")
    }
}
