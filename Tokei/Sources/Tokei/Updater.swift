import Foundation
import AppKit

final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, available(String, URL), failed(String)
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate): return true
            case (.available(let a, _), .available(let b, _)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    static let releaseTag = "v1.0.1"
    @Published var state: State = .idle

    private let apiURL = URL(string: "https://api.github.com/repos/cclank/tokei/releases/latest")!

    static let shared = Updater()

    private static func isNewer(remote: String, local: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                .split(separator: ".").compactMap { Int($0) }
        }
        let r = parse(remote), l = parse(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    func checkForUpdate() {
        guard state == .idle || state == .upToDate || {
            if case .failed = state { return true }; return false
        }() else { return }
        state = .checking
        var req = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    self?.state = .idle
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    self.state = .idle
                    return
                }
                let urlStr = json["html_url"] as? String
                    ?? "https://github.com/cclank/tokei/releases/tag/\(tag)"
                guard
                      let url = URL(string: urlStr) else {
                    self.state = .idle
                    return
                }
                if Self.isNewer(remote: tag, local: Self.releaseTag) {
                    self.state = .available(tag, url)
                } else {
                    self.state = .upToDate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        if self?.state == .upToDate { self?.state = .idle }
                    }
                }
            }
        }.resume()
    }
}
