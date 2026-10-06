import Foundation
import Darwin

public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let uid: UInt32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, uid: UInt32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid
        self.uid = uid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }

    public var canTerminate: Bool { pid > 1 && pid != getpid() && uid == geteuid() }
    public var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startSeconds)) }
}

public struct Listener: Identifiable, Equatable, Sendable {
    public struct ID: Hashable, Sendable {
        public let process: ProcessIdentity
        public let port: UInt16
    }

    public let process: ProcessIdentity
    public let name: String
    public let port: UInt16
    public var addresses: Set<String>
    public var id: ID { ID(process: process, port: port) }

    public init(process: ProcessIdentity, name: String, port: UInt16, addresses: Set<String>) {
        self.process = process
        self.name = name.isEmpty ? "Process" : name
        self.port = port
        self.addresses = addresses
    }

    public var host: String {
        if !addresses.isDisjoint(with: ["127.0.0.1", "::1", "0.0.0.0", "::"]) { return "localhost" }
        return addresses.sorted().first ?? "localhost"
    }

    public var httpURL: URL { URL(string: "http://\(host):\(port)")! }

    public var listensOnAllInterfaces: Bool { !addresses.isDisjoint(with: ["0.0.0.0", "::"]) }

    static let nonWebPorts: Set<UInt16> = [22, 25, 53, 110, 143, 465, 587, 993, 995, 1433, 2376, 3306, 5432, 5672, 6379, 6380, 9042, 9092, 9229, 9230, 11211, 27017, 33060]

    /// Conservative hints, not protocol detection. Icon discovery uses these hints too.
    public var suggestedWebURL: URL? {
        let command = name.lowercased()
        let nonWebNames = ["redis", "mysqld", "postgres", "mongod", "memcached", "sshd", "rapportd", "controlcenter"]
        guard !nonWebNames.contains(where: command.contains), !Self.nonWebPorts.contains(port) else { return nil }
        if [443, 4443, 8443].contains(port) { return URL(string: "https://\(host):\(port)") }
        let webNames = ["node", "bun", "deno", "python", "python3", "python2", "ruby", "php", "httpd", "nginx", "caddy", "uvicorn", "gunicorn", "vite", "next-server", "dotnet"]
        let webPorts: Set<UInt16> = [80, 4200, 4321, 5500, 8000, 8001, 8008, 8080, 8081, 8088, 8888, 9000, 9090]
        if webNames.contains(where: { command == $0 || command.hasPrefix($0 + ".") || command.hasPrefix($0 + "-") }) ||
            webPorts.contains(port) || (3000...3010).contains(port) || (4000...4010).contains(port) ||
            (5000...5010).contains(port) || (5173...5190).contains(port) {
            return httpURL
        }
        return nil
    }

    public static func merged(_ listeners: [Listener]) -> [Listener] {
        var result: [ID: Listener] = [:]
        for listener in listeners {
            if var previous = result[listener.id] {
                previous.addresses.formUnion(listener.addresses)
                result[listener.id] = previous
            } else { result[listener.id] = listener }
        }
        return result.values.sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            return $0.process.pid < $1.process.pid
        }
    }
}
