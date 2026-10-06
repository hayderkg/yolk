import Foundation

public enum ServiceCategory: String, CaseIterable, Identifiable, Sendable {
    case development, database, application, system, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .development: return "Development"
        case .database: return "Databases"
        case .application: return "Apps"
        case .system: return "System"
        case .other: return "Other"
        }
    }
}

public struct ProcessDetails: Equatable, Sendable {
    public let executablePath: String
    public let workingDirectory: String
    public let arguments: [String]

    public init(executablePath: String = "", workingDirectory: String = "", arguments: [String] = []) {
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.arguments = arguments
    }

    public var appBundleURL: URL? {
        let components = NSString(string: executablePath).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index])), isDirectory: true)
    }
}

public struct ServiceIdentity: Equatable, Sendable {
    public let category: ServiceCategory
    public let projectName: String?
    public let projectDirectory: URL?
    public let appBundleURL: URL?
    public let executablePath: String?
    /// Shortened command line, when macOS exposes it to this user.
    public let command: String?
    /// Set when the listener is an engine proxy publishing this container's port.
    public let container: ContainerInfo?

    public init(listener: Listener, details: ProcessDetails? = nil, container: ContainerInfo? = nil, readProject: Bool = true) {
        self.container = container
        category = Self.category(for: listener, details: details, container: container)
        appBundleURL = details?.appBundleURL
        executablePath = details?.executablePath.isEmpty == false ? details?.executablePath : nil
        command = container == nil ? details.flatMap { CommandSummary.make($0.arguments) } : nil
        if let container {
            projectName = container.name
            projectDirectory = nil
        } else if category == .development, let path = details?.workingDirectory, path.hasPrefix("/"),
           path != "/", path != FileManager.default.homeDirectoryForCurrentUser.path {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let project = readProject ? Self.findProject(in: directory) : nil
            projectDirectory = project?.directory ?? directory
            projectName = project?.name ?? directory.lastPathComponent
        } else {
            projectName = nil
            projectDirectory = nil
        }
    }

    /// Browser target: the listener's own hint, or plain HTTP for a non-database container.
    public func webURL(for listener: Listener) -> URL? {
        if let url = listener.suggestedWebURL { return url }
        guard let container, !container.isDatabase, !Listener.nonWebPorts.contains(listener.port) else { return nil }
        return listener.httpURL
    }

    public static func category(for listener: Listener, details: ProcessDetails? = nil, container: ContainerInfo? = nil) -> ServiceCategory {
        if let container { return container.isDatabase ? .database : .development }
        let name = listener.name.lowercased()
        let executable = details?.executablePath ?? ""
        if executable.hasPrefix("/System/") || executable.hasPrefix("/usr/libexec/") ||
            ["controlcenter", "rapportd", "sharingd", "airplayxpchelper", "mDNSResponder".lowercased(), "sshd", "cupsd"].contains(name) {
            return .system
        }
        if ["mysqld", "mariadbd", "postgres", "postmaster", "redis-server", "redis-stack-server", "mongod", "mongos", "memcached", "cockroach", "valkey-server"].contains(where: { name == $0 || name.hasPrefix($0 + ".") }) {
            return .database
        }
        if details?.appBundleURL != nil { return .application }
        if isDevelopmentRuntime(name) || listener.suggestedWebURL != nil { return .development }
        return .other
    }

    public static func isDevelopmentRuntime(_ name: String) -> Bool {
        let runtimes = ["node", "bun", "deno", "python", "python3", "python2", "ruby", "php", "java", "dotnet", "go", "cargo", "nginx", "httpd", "caddy", "uvicorn", "gunicorn", "vite", "next-server"]
        return runtimes.contains { name == $0 || name.hasPrefix($0 + ".") || name.hasPrefix($0 + "-") }
    }

    public static func initials(for title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let first = words.first else { return "?" }
        if words.count > 1 { return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased() }
        return String(first.prefix(2)).uppercased()
    }

    private static func findProject(in workingDirectory: URL) -> (name: String, directory: URL)? {
        var directory = workingDirectory
        for _ in 0..<4 {
            if directory.path == "/" || directory == FileManager.default.homeDirectoryForCurrentUser { break }
            let file = directory.appendingPathComponent("package.json")
            if let handle = try? FileHandle(forReadingFrom: file) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 65_537), data.count <= 65_536,
                   let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let raw = package["name"] as? String {
                    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                        return (name, directory)
                    }
                }
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
