import AppKit
import SwiftUI
import Combine
import CryptoKit
import SQLite3

private struct UsageWindow: Identifiable {
    let id: String
    let title: String
    let used: Double
    let resetAt: Date?
}

private struct ProviderUsage {
    var name: String
    var windows: [UsageWindow] = []
    var message = "Loading…"
    var updatedAt: Date?
}

@MainActor
private final class UsageStore: ObservableObject {
    @Published var codex = ProviderUsage(name: "Codex")
    @Published var claude = ProviderUsage(name: "Claude Code")
    @Published var antigravity = ProviderUsage(name: "Antigravity")
    @Published var cursor = ProviderUsage(name: "Cursor")
    @Published var grok = ProviderUsage(name: "Grok Bot")
    @Published var cursorGrokPoolIsShared = false
    @Published var isRefreshing = false

    private var timer: Timer?

    init() {
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let codexResult = Self.fetchCodex()
            async let claudeResult = Self.fetchClaude()
            async let antigravityResult = Self.fetchAntigravity()
            async let cursorResult = Self.fetchCursorGrok()
            let (codexValue, claudeValue, antigravityValue, (cursorValue, isUnified)) = await (codexResult, claudeResult, antigravityResult, cursorResult)
            codex = codexValue
            claude = claudeValue
            antigravity = antigravityValue
            cursor = cursorValue
            cursorGrokPoolIsShared = isUnified
            grok = isUnified
                ? ProviderUsage(name: "Grok Bot", windows: cursorValue.windows,
                                message: cursorValue.message, updatedAt: cursorValue.updatedAt)
                : ProviderUsage(name: "Grok Bot", message: "Grok Bot usage is shown in its account dashboard.")
            isRefreshing = false
        }
    }

    private static func fetchCodex() async -> ProviderUsage {
        var result = ProviderUsage(name: "Codex")
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty,
              let accountID = tokens["account_id"] as? String, !accountID.isEmpty else {
            result.message = "Sign in to Codex to see usage."
            return result
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result.message = "Could not read usage. Check your Codex sign-in."
                return result
            }
            let limits = (json["rate_limit"] as? [String: Any]) ?? (json["rate_limits"] as? [String: Any]) ?? json
            for (key, title) in [("primary_window", "Current window"), ("secondary_window", "Weekly window")] {
                guard let window = limits[key] as? [String: Any],
                      let used = number(window["used_percent"]) else { continue }
                result.windows.append(UsageWindow(id: key, title: title, used: used,
                                                  resetAt: date(window["reset_at"])))
            }
            result.message = result.windows.isEmpty ? "No usage windows returned." : ""
            result.updatedAt = Date()
        } catch {
            result.message = "Unable to reach the Codex usage service."
        }
        return result
    }

    private static func fetchClaude() async -> ProviderUsage {
        var result = ProviderUsage(name: "Claude Code")
        guard let token = claudeToken(), !token.isEmpty else {
            result.message = "Sign in to Claude Code to see usage."
            return result
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result.message = "Could not read usage. Check your Claude sign-in."
                return result
            }
            for (key, title) in [("five_hour", "5-hour window"), ("seven_day", "Weekly window"),
                                 ("seven_day_sonnet", "Sonnet weekly"), ("seven_day_opus", "Opus weekly")] {
                guard let window = json[key] as? [String: Any],
                      let used = number(window["utilization"]) else { continue }
                result.windows.append(UsageWindow(id: key, title: title, used: used,
                                                  resetAt: date(window["resets_at"])))
            }
            result.message = result.windows.isEmpty ? "No usage windows returned." : ""
            result.updatedAt = Date()
        } catch {
            result.message = "Unable to reach the Claude usage service."
        }
        return result
    }

    /// Antigravity has no documented public usage API. Its desktop app requests
    /// these Cloud Code endpoints using the OAuth access token it already stores.
    private static func fetchAntigravity() async -> ProviderUsage {
        var result = ProviderUsage(name: "Antigravity")
        guard let token = antigravityToken() else {
            result.message = "Sign in to Antigravity to see usage."
            return result
        }

        let bases = [
            "https://daily-cloudcode-pa.googleapis.com",
            "https://cloudcode-pa.googleapis.com"
        ]
        var hadResponse = false
        for base in bases {
            guard let setup = await antigravityRequest(
                "\(base)/v1internal:loadCodeAssist", token: token,
                body: ["metadata": ["ideType": "ANTIGRAVITY"]]
            ) else { continue }
            hadResponse = true

            guard let project = findString(in: setup, keys: ["cloudaicompanionProject", "cloud_ai_companion_project"]),
                  !project.isEmpty else {
                result.message = "Antigravity did not return a quota project."
                continue
            }
            guard let response = await antigravityRequest(
                "\(base)/v1internal:fetchAvailableModels", token: token,
                body: ["project": project]
            ) else { continue }

            let values: [(String, [String: Any])]
            if let models = response["models"] as? [String: [String: Any]] {
                values = models.map { ($0.key, $0.value) }
            } else if let models = response["models"] as? [[String: Any]] {
                values = models.enumerated().map { ("model-\($0.offset)", $0.element) }
            } else {
                result.message = "Antigravity returned an unexpected model list."
                continue
            }

            var seen = Set<String>()
            for (id, model) in values {
                guard model["isInternal"] as? Bool != true,
                      let title = (model["displayName"] as? String) ?? (model["display_name"] as? String),
                      !title.isEmpty,
                      let quota = (model["quotaInfo"] as? [String: Any]) ?? (model["quota_info"] as? [String: Any]),
                      let remaining = number(quota["remainingFraction"] ?? quota["remaining_fraction"]),
                      (0...1).contains(remaining) else { continue }
                let reset = date(quota["resetTime"] ?? quota["reset_time"])
                let identity = "\(title)|\(reset?.timeIntervalSince1970 ?? -1)|\(remaining)"
                guard seen.insert(identity).inserted else { continue }
                result.windows.append(UsageWindow(id: id, title: title,
                                                  used: (1 - remaining) * 100, resetAt: reset))
            }
            result.windows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            result.message = result.windows.isEmpty ? "No Antigravity model quotas returned." : ""
            result.updatedAt = Date()
            return result
        }
        result.message = hadResponse
            ? "Could not read Antigravity model quotas."
            : "Unable to reach the Antigravity usage service."
        return result
    }

    private static func antigravityRequest(_ url: String, token: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: url),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = data
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
    }

    /// Cursor's desktop client and Grok Bot expose the same first-party weekly
    /// pool through Cursor's DashboardService. This is an app API rather than
    /// a documented public API, so failures leave the dashboard links available.
    private static func fetchCursorGrok() async -> (ProviderUsage, Bool) {
        var result = ProviderUsage(name: "Cursor & Grok Bot")
        guard let (token, machineID) = cursorCredentials() else {
            result.message = "Sign in to Cursor to see usage."
            return (result, false)
        }

        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        // This is a unary Connect call, so the empty protobuf request has no body framing.
        request.httpBody = Data()
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/proto", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("sand", forHTTPHeaderField: "x-cursor-client-type")
        request.setValue("1.0.0", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("CLIENT_OS_MACOS", forHTTPHeaderField: "x-cursor-client-os")
        request.setValue("prod", forHTTPHeaderField: "x-sand-box-namespace")
        request.setValue("true", forHTTPHeaderField: "x-ghost-mode")
        request.setValue(cursorChecksum(machineID), forHTTPHeaderField: "x-cursor-checksum")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Sand/1.0.0 Safari/537.36",
                         forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                result.message = "Cursor/Grok returned an invalid response."
                return (result, false)
            }
            guard (200..<300).contains(http.statusCode) else {
                result.message = "Cursor/Grok usage request failed (HTTP \(http.statusCode)). Reopen Cursor and refresh."
                return (result, false)
            }
            guard let usage = protoDouble(field: 3, in: data) else {
                result.message = "Cursor/Grok returned usage data in an unexpected format."
                return (result, false)
            }
            let isUnified = protoBool(field: 18, in: data) ?? false
            let resetAt = protoTimestamp(field: 2, in: data)
            result.name = isUnified ? "Cursor & Grok Bot" : "Cursor"
            result.windows.append(UsageWindow(id: "included-usage", title: isUnified ? "Shared weekly pool" : "Included usage",
                                              used: usage, resetAt: resetAt))
            result.message = ""
            result.updatedAt = Date()
            return (result, isUnified)
        } catch {
            result.message = "Unable to reach the Cursor/Grok usage service."
            return (result, false)
        }
    }

    private static func cursorCredentials() -> (String, String)? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return nil }
        defer { sqlite3_close(database) }

        func read(_ key: String) -> String? {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ?1", -1,
                                     &statement, nil) == SQLITE_OK else { return nil }
            _ = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let value = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: value)
        }

        guard let token = read("cursorAuth/accessToken"), !token.isEmpty,
              let machineID = read("storage.serviceMachineId"), !machineID.isEmpty else { return nil }
        return (token, machineID)
    }

    private static func antigravityToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb").path
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return nil }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ?1", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        _ = "antigravityAuthStatus".withCString {
            sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              let data = String(cString: value).data(using: .utf8),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = auth["apiKey"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private static func cursorChecksum(_ machineID: String) -> String {
        let seconds = UInt64(Date().timeIntervalSince1970)
        var bytes = (0..<6).map { shift in UInt8((seconds >> (40 - shift * 8)) & 0xff) }
        for index in bytes.indices { bytes[index] = (bytes[index] ^ 165) &+ UInt8(index) }
        let encoded = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded + machineID
    }

    private static func protoDouble(field: Int, in data: Data) -> Double? {
        var index = 0
        while index < data.count {
            guard let key = readVarint(data, &index) else { return nil }
            let number = Int(key >> 3)
            let wireType = key & 7
            if number == field, wireType == 1, index + 8 <= data.count {
                let bits = data[index..<index + 8].enumerated().reduce(UInt64(0)) {
                    $0 | (UInt64($1.element) << ($1.offset * 8))
                }
                return Double(bitPattern: bits)
            }
            guard skipProtoValue(wireType, data, &index) else { return nil }
        }
        return nil
    }

    private static func protoBool(field: Int, in data: Data) -> Bool? {
        var index = 0
        while index < data.count {
            guard let key = readVarint(data, &index) else { return nil }
            let number = Int(key >> 3)
            let wireType = key & 7
            if number == field, wireType == 0, let value = readVarint(data, &index) {
                return value != 0
            }
            guard skipProtoValue(wireType, data, &index) else { return nil }
        }
        return nil
    }

    private static func protoTimestamp(field: Int, in data: Data) -> Date? {
        var index = 0
        while index < data.count {
            guard let key = readVarint(data, &index) else { return nil }
            let wireType = key & 7
            if Int(key >> 3) == field, wireType == 2,
               let count = readVarint(data, &index), Int(count) <= data.count - index {
                let end = index + Int(count)
                var seconds: Int64 = 0
                var nested = index
                while nested < end {
                    guard let nestedKey = readVarint(data, &nested) else { return nil }
                    if nestedKey >> 3 == 1, nestedKey & 7 == 0,
                       let value = readVarint(data, &nested) { seconds = Int64(bitPattern: value) }
                    else if !skipProtoValue(nestedKey & 7, data, &nested) { return nil }
                }
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }
            guard skipProtoValue(wireType, data, &index) else { return nil }
        }
        return nil
    }

    private static func readVarint(_ data: Data, _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count && shift < 64 {
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private static func skipProtoValue(_ wireType: UInt64, _ data: Data, _ index: inout Int) -> Bool {
        switch wireType {
        case 0: return readVarint(data, &index) != nil
        case 1:
            guard data.count - index >= 8 else { return false }
            index += 8
            return true
        case 2:
            guard let length = readVarint(data, &index), Int(length) <= data.count - index else { return false }
            index += Int(length)
            return true
        case 5:
            guard data.count - index >= 4 else { return false }
            index += 4
            return true
        default: return false
        }
    }

    private static func claudeToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = root["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty { return token }

        // Claude Code stores OAuth credentials in the login Keychain on macOS.
        let hash = SHA256.hash(data: Data(file.deletingLastPathComponent().path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let services = ["Claude Code-credentials", "Claude Code-credentials-\(hash.prefix(8))"]
        for service in services {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-a", NSUserName(), "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0,
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let oauth = root["claudeAiOauth"] as? [String: Any],
                   let token = oauth["accessToken"] as? String, !token.isEmpty { return token }
            } catch { continue }
        }
        return ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func findString(in value: Any, keys: Set<String>) -> String? {
        if let object = value as? [String: Any] {
            for (key, value) in object {
                if keys.contains(key), let string = value as? String { return string }
                if let string = findString(in: value, keys: keys) { return string }
            }
        } else if let values = value as? [Any] {
            for value in values {
                if let string = findString(in: value, keys: keys) { return string }
            }
        }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value), seconds > 10_000_000_000 { return Date(timeIntervalSince1970: seconds / 1000) }
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: string)
        }
        return nil
    }
}

@main
struct UsageBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 14) {
                ProviderView(usage: store.codex)
                Divider()
                ProviderView(usage: store.claude)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ProviderView(usage: store.antigravity)
                    UsageDashboardLink(title: "Antigravity", url: "https://antigravity.google/")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ProviderView(usage: store.cursor)
                    Text(store.cursorGrokPoolIsShared
                         ? "Cursor and Grok Bot use the same included weekly pool on X Subscription."
                         : "Grok Bot usage may be separate. Check each account dashboard for its usage.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    UsageDashboardLink(title: "Cursor", url: "https://cursor.com/dashboard")
                    UsageDashboardLink(title: "Grok Bot", url: "https://grok.com/dashboard")
                }
                Divider()
                HStack {
                    if let date = [store.codex.updatedAt, store.claude.updatedAt, store.antigravity.updatedAt, store.cursor.updatedAt].compactMap({ $0 }).max() {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isRefreshing ? "Refreshing…" : "Refresh") { store.refresh() }
                        .disabled(store.isRefreshing)
                }.font(.caption)
            }
            .padding(14)
            .frame(width: 310)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarSymbol)
                if !menuBarValues.isEmpty {
                    Text(menuBarValues)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text("AI")
                }
            }
            .font(.system(size: 10))
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarValues: String {
        let providers: [(String, ProviderUsage)] = [
            ("Codex", store.codex),
            ("CC", store.claude),
            ("AG", store.antigravity),
            ("Cursor", store.cursor),
            ("Grok", store.grok)
        ]
        let available = providers.compactMap { name, usage -> String? in
            guard let window = usage.windows.first else { return nil }
            return "\(name): \(Int(window.used.rounded()))%"
        }
        return available.joined(separator: " · ")
    }

    private var menuBarSymbol: String {
        menuBarValues.isEmpty ? "chart.bar.xaxis" : "chart.bar.fill"
    }
}

private struct UsageDashboardLink: View {
    let title: String
    let url: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Link("Open dashboard", destination: URL(string: url)!)
                .font(.caption)
        }
    }
}

private struct ProviderView: View {
    let usage: ProviderUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(usage.name).font(.headline)
            if usage.windows.isEmpty {
                Text(usage.message).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(usage.windows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.title)
                            Spacer()
                            Text("\(Int(window.used.rounded()))% used")
                                .monospacedDigit()
                        }.font(.callout)
                        ProgressView(value: min(max(window.used, 0), 100), total: 100)
                        if let resetAt = window.resetAt {
                            Text("Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
