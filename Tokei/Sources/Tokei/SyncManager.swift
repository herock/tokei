import Foundation

struct SyncConfig: Codable {
    var device_id: String
    var sync_dir: String
    var auto_sync: Bool?
    var sync_interval: Int?     // minutes
}

struct PeerDevice: Identifiable {
    var id: String { deviceId }
    var deviceId: String
    var lastSync: Date
    var usage: Usage
}

final class SyncManager {
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tokei/config.json")

    var config: SyncConfig?

    init() { config = Self.loadConfig() }

    // MARK: - Config

    static func loadConfig() -> SyncConfig? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(SyncConfig.self, from: data)
    }

    func saveConfig(_ cfg: SyncConfig) {
        config = cfg
        let dir = Self.configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: Self.configPath)
        }
    }

    // MARK: - Read peers

    func loadPeers() -> [PeerDevice] {
        guard let cfg = config, !cfg.sync_dir.isEmpty else { return [] }
        let dir = (cfg.sync_dir as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dir) else { return [] }
        var peers: [PeerDevice] = []
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        for file in files where file.hasSuffix(".json") {
            let deviceId = String(file.dropLast(5)) // remove .json
            if deviceId == cfg.device_id { continue }
            let path = (dir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = raw["_ts"] as? Int else { continue }
            // Re-decode without _device/_ts (Usage struct doesn't have them)
            var cleaned = raw
            cleaned.removeValue(forKey: "_device")
            cleaned.removeValue(forKey: "_ts")
            guard let cleanData = try? JSONSerialization.data(withJSONObject: cleaned),
                  let usage = try? JSONDecoder().decode(Usage.self, from: cleanData) else { continue }
            peers.append(PeerDevice(
                deviceId: deviceId,
                lastSync: Date(timeIntervalSince1970: TimeInterval(ts)),
                usage: usage
            ))
        }
        return peers
    }

    // MARK: - Merge

    static func merge(local: Usage, peers: [PeerDevice]) -> Usage {
        var u = local
        for peer in peers {
            mergeRanges(&u.claude.ranges, peer.usage.claude.ranges)
            mergeRanges(&u.codex.ranges, peer.usage.codex.ranges)
            mergeRanges(&u.gemini.ranges, peer.usage.gemini.ranges)
            mergeRanges(&u.grok.ranges, peer.usage.grok.ranges)
            mergeRanges(&u.qoder.ranges, peer.usage.qoder.ranges)
        }
        return u
    }

    private static func mergeRanges(_ dst: inout ClaudeRanges, _ src: ClaudeRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cr += s.cr; d.cw += s.cw
            d.cost += s.cost; d.sessions += s.sessions
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout CodexRanges, _ src: CodexRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cached += s.cached
            d.reason += s.reason; d.cost += s.cost; d.sessions += s.sessions
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout GeminiRanges, _ src: GeminiRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.cached += s.cached
            d.thoughts += s.thoughts; d.cost += s.cost; d.sessions += s.sessions
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout GrokRanges, _ src: GrokRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.tokens += s.tokens; d.sessions += s.sessions
            dst.set(k, d)
        }
    }

    private static func mergeRanges(_ dst: inout QoderRanges, _ src: QoderRanges) {
        for k in RangeKey.allCases {
            var d = dst.get(k), s = src.get(k)
            d.in += s.in; d.out += s.out; d.sessions += s.sessions
            d.calls += s.calls; d.duration += s.duration
            dst.set(k, d)
        }
    }

    // MARK: - Git sync

    func gitSync(completion: @escaping (Bool) -> Void) {
        guard let cfg = config, !cfg.sync_dir.isEmpty else { completion(false); return }
        let dir = (cfg.sync_dir as NSString).expandingTildeInPath
        DispatchQueue.global(qos: .utility).async {
            let script = """
            cd "\(dir)" && \
            git pull --rebase --autostash 2>/dev/null; \
            git add -A && \
            (git diff --cached --quiet || git commit -m "tokei sync \(cfg.device_id)") && \
            git push 2>/dev/null
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", script]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }
    }
}
