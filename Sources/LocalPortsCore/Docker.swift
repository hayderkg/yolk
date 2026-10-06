import Foundation
import Darwin

public struct ContainerInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let ports: Set<UInt16>

    public init(id: String, name: String, image: String, ports: Set<UInt16>) {
        self.id = id
        self.name = name
        self.image = image
        self.ports = ports
    }

    /// `ghcr.io/acme/api:1.2` reads as `api:1.2`.
    public var imageName: String {
        if image.hasPrefix("sha256:") { return String(image.dropFirst(7).prefix(12)) }
        return image.split(separator: "/").last.map(String.init) ?? image
    }

    public var isDatabase: Bool {
        let name = (imageName.split(separator: ":").first.map(String.init) ?? imageName).lowercased()
        return ["postgres", "postgis", "mysql", "mariadb", "redis", "valkey", "mongo", "memcached", "cockroach", "clickhouse", "timescaledb"]
            .contains(where: name.hasPrefix)
    }
}

/// Reads published ports from the local Docker-compatible engine over its Unix socket.
public enum Docker {
    public static var socketPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.docker/run/docker.sock", "\(home)/.orbstack/run/docker.sock",
                "\(home)/.colima/default/docker.sock", "\(home)/.rd/docker.sock", "/var/run/docker.sock"]
    }

    /// Host processes that publish container ports on behalf of the engine.
    public static func isProxy(_ processName: String) -> Bool {
        let name = processName.lowercased()
        return name.hasPrefix("com.docker") || name.hasPrefix("docker") || name.contains("orbstack") ||
            name == "vpnkit" || name == "gvproxy" || name == "limactl"
    }

    public static func containers(socketPaths: [String] = Docker.socketPaths) -> [ContainerInfo] {
        for path in socketPaths {
            guard let response = request("GET", "/containers/json", socketPath: path, timeout: 2) else { continue }
            return response.status == 200 ? parseContainers(response.body) : []
        }
        return []
    }

    public static func stop(containerID: String, socketPaths: [String] = Docker.socketPaths) -> Bool {
        guard !containerID.isEmpty, containerID.count <= 64, containerID.allSatisfy(\.isHexDigit) else { return false }
        for path in socketPaths {
            guard let response = request("POST", "/containers/\(containerID)/stop?t=5", socketPath: path, timeout: 20) else { continue }
            return response.status == 204 || response.status == 304
        }
        return false
    }

    public static func parseContainers(_ data: Data) -> [ContainerInfo] {
        struct Entry: Decodable {
            struct Port: Decodable { let PublicPort: Int?; let `Type`: String? }
            let Id: String
            let Names: [String]?
            let Image: String?
            let Ports: [Port]?
        }
        guard data.count <= 2_000_000, let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { entry in
            let ports = Set((entry.Ports ?? []).compactMap { port -> UInt16? in
                guard port.`Type` ?? "tcp" == "tcp", let number = port.PublicPort else { return nil }
                return UInt16(exactly: number)
            })
            guard !ports.isEmpty else { return nil }
            let name = entry.Names?.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(entry.Id.prefix(12))
            return ContainerInfo(id: entry.Id, name: name, image: entry.Image ?? "", ports: ports)
        }
    }

    static func parseResponse(_ data: Data) -> (status: Int, body: Data)? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8),
              let statusLine = head.split(separator: "\r\n").first else { return nil }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let status = Int(parts[1]) else { return nil }
        return (status, Data(data[separator.upperBound...]))
    }

    /// HTTP/1.0 keeps the reply unchunked and closes the socket, so reading to EOF is the whole body.
    static func request(_ method: String, _ path: String, socketPath: String, timeout: Int) -> (status: Int, body: Data)? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var limit = timeval(tv_sec: timeout, tv_usec: 0)
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        let message = Array("\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\n\r\n".utf8)
        var sent = 0
        while sent < message.count {
            let written = message[sent...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            guard written > 0 else { return nil }
            sent += written
        }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while received.count <= 2_000_000 {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else { return nil }
            received.append(buffer, count: count)
        }
        return parseResponse(received)
    }
}
