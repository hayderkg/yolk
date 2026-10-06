import Foundation

/// Short, display-only form of a process command line. Never persisted.
public enum CommandSummary {
    private static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby", "php", "tsx", "ts-node"]
    private static let sensitive = ["token", "secret", "password", "passwd", "key", "auth", "credential"]

    public static func make(_ arguments: [String], limit: Int = 60) -> String? {
        guard let first = arguments.first, !first.isEmpty else { return nil }
        var words: [String] = []
        var redactNext = false
        for (index, raw) in arguments.prefix(24).enumerated() {
            let argument = String(raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
            if redactNext { words.append("•••"); redactNext = false; continue }
            if index == 0 { words.append(shortened(argument)); continue }
            guard argument.hasPrefix("-") else { words.append(shortened(withoutCredentials(argument))); continue }
            if let separator = argument.firstIndex(of: "=") {
                let key = String(argument[..<separator])
                let value = String(argument[argument.index(after: separator)...])
                words.append(key + "=" + (isSensitive(key) ? "•••" : shortened(withoutCredentials(value))))
            } else {
                words.append(argument)
                redactNext = isSensitive(argument)
            }
        }
        // `node …/node_modules/.bin/vite` reads better as `vite`.
        if words.count > 1, interpreters.contains(words[0].lowercased()), arguments[1].contains("/node_modules/") {
            words.removeFirst()
        }
        let summary = words.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !summary.isEmpty else { return nil }
        return summary.count > limit ? String(summary.prefix(limit - 1)) + "…" : summary
    }

    private static func isSensitive(_ flag: String) -> Bool {
        let name = flag.lowercased()
        return sensitive.contains(where: name.contains)
    }

    private static func withoutCredentials(_ text: String) -> String {
        guard let scheme = text.range(of: "://"), let at = text[scheme.upperBound...].firstIndex(of: "@"),
              !text[scheme.upperBound..<at].contains("/") else { return text }
        return text[..<scheme.upperBound] + "•••" + text[at...]
    }

    private static func shortened(_ path: String) -> String {
        if let modules = path.range(of: "/node_modules/", options: .backwards) {
            let parts = path[modules.upperBound...].split(separator: "/").map(String.init)
            if parts.first == ".bin", parts.count > 1 { return parts[1] }
            if let package = parts.first, package.hasPrefix("@"), parts.count > 1 { return package + "/" + parts[1] }
            if let package = parts.first { return package }
        }
        guard path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("./") || path.hasPrefix("../") else { return path }
        return NSString(string: path).lastPathComponent
    }
}

public enum Uptime {
    public static func short(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }
}
