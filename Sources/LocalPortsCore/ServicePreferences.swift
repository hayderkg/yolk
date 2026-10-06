import Foundation

public struct SavedService: Codable, Equatable, Sendable {
    public let title: String
    public let port: UInt16
}

/// Saved by project/application + process name + port, never by a transient PID.
public struct ServicePreferences: Codable, Equatable, Sendable {
    public private(set) var favorites: [String: SavedService] = [:]
    public private(set) var hidden: [String: SavedService] = [:]

    public init(data: Data? = nil) {
        if let data, let saved = try? JSONDecoder().decode(Self.self, from: data) { self = saved }
    }

    public var data: Data? { try? JSONEncoder().encode(self) }

    public static func key(for listener: Listener, service: ServiceIdentity) -> String {
        let owner = service.projectDirectory?.standardizedFileURL.path ?? service.appBundleURL?.path ?? service.executablePath ?? listener.name
        let components = [owner, listener.name, String(listener.port)]
        // JSON avoids delimiter collisions in directory and process names.
        return String(decoding: try! JSONEncoder().encode(components), as: UTF8.self)
    }

    public func isFavorite(_ listener: Listener, service: ServiceIdentity) -> Bool {
        favorites[Self.key(for: listener, service: service)] != nil
    }

    public func isHidden(_ listener: Listener, service: ServiceIdentity) -> Bool {
        hidden[Self.key(for: listener, service: service)] != nil
    }

    public mutating func toggleFavorite(_ listener: Listener, service: ServiceIdentity) {
        let key = Self.key(for: listener, service: service)
        if favorites.removeValue(forKey: key) == nil {
            favorites[key] = SavedService(title: service.projectName ?? listener.name, port: listener.port)
        }
    }

    public mutating func toggleHidden(_ listener: Listener, service: ServiceIdentity) {
        let key = Self.key(for: listener, service: service)
        if hidden.removeValue(forKey: key) == nil {
            hidden[key] = SavedService(title: service.projectName ?? listener.name, port: listener.port)
        }
    }

    public mutating func restoreHidden(key: String) { hidden[key] = nil }
    public mutating func restoreAllHidden() { hidden = [:] }
}

public enum ServiceList {
    public static func filtered(_ listeners: [Listener], services: [Listener.ID: ServiceIdentity],
                                preferences: ServicePreferences, query: String = "",
                                favoritesOnly: Bool = false, showHidden: Bool = false) -> [Listener] {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let terms = normalized(query).split(whereSeparator: \.isWhitespace)
        return listeners.filter { listener in
            let service = services[listener.id] ?? ServiceIdentity(listener: listener)
            guard showHidden || !preferences.isHidden(listener, service: service),
                  !favoritesOnly || preferences.isFavorite(listener, service: service) else { return false }
            let searchable = normalized([listener.name, service.projectName ?? "", String(listener.process.pid),
                                         String(listener.port), service.category.title,
                                         service.projectDirectory?.path ?? "", service.command ?? "",
                                         service.container?.image ?? ""].joined(separator: " "))
            return terms.allSatisfy { searchable.contains($0) }
        }.sorted { lhs, rhs in
            let left = preferences.isFavorite(lhs, service: services[lhs.id] ?? ServiceIdentity(listener: lhs))
            let right = preferences.isFavorite(rhs, service: services[rhs.id] ?? ServiceIdentity(listener: rhs))
            if left != right { return left }
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.process.pid < rhs.process.pid
        }
    }
}
