import XCTest
import Foundation
import Darwin
@testable import LocalPortsCore

final class CommandAndDockerTests: XCTestCase {
    func testCommandSummaryShortensPathsAndDropsInterpreterForPackageBinaries() {
        XCTAssertEqual(CommandSummary.make(["/opt/homebrew/bin/node", "/Users/me/app/node_modules/.bin/vite", "--port", "3000"]), "vite --port 3000")
        XCTAssertEqual(CommandSummary.make(["node", "/Users/me/app/node_modules/next/dist/bin/next", "dev"]), "next dev")
        XCTAssertEqual(CommandSummary.make(["node", "/Users/me/app/node_modules/@angular/cli/bin/ng.js", "serve"]), "@angular/cli serve")
        XCTAssertEqual(CommandSummary.make(["/usr/bin/python3", "-m", "http.server", "8000"]), "python3 -m http.server 8000")
        XCTAssertEqual(CommandSummary.make(["/usr/local/bin/node", "/Users/me/app/server.js"]), "node server.js")
        XCTAssertNil(CommandSummary.make([]))
        XCTAssertNil(CommandSummary.make([""]))
    }

    func testCommandSummaryRedactsSecretsAndStaysBounded() {
        XCTAssertEqual(CommandSummary.make(["app", "--api-key=abc123", "--port=80"]), "app --api-key=••• --port=80")
        XCTAssertEqual(CommandSummary.make(["app", "--token", "abc123", "serve"]), "app --token ••• serve")
        XCTAssertEqual(CommandSummary.make(["app", "postgres://admin:hunter2@localhost/db"]), "app postgres://•••@localhost/db")
        XCTAssertEqual(CommandSummary.make(["app", "--db=mysql://root:pw@127.0.0.1/x"]), "app --db=mysql://•••@127.0.0.1/x")
        let long = try! XCTUnwrap(CommandSummary.make(["app"] + Array(repeating: "argument", count: 40)))
        XCTAssertEqual(long.count, 60)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertFalse(try! XCTUnwrap(CommandSummary.make(["app", "line\nbreak"])).contains("\n"))
    }

    func testUptimeUsesOneCompactUnit() {
        XCTAssertEqual(Uptime.short(-5), "<1m")
        XCTAssertEqual(Uptime.short(59), "<1m")
        XCTAssertEqual(Uptime.short(60), "1m")
        XCTAssertEqual(Uptime.short(3_599), "59m")
        XCTAssertEqual(Uptime.short(7_300), "2h")
        XCTAssertEqual(Uptime.short(3 * 86_400 + 5), "3d")
    }

    func testOwnArgumentsAreReadable() throws {
        let identity = try ProcessInspector.identity(pid: getpid())
        let arguments = ProcessInspector.arguments(for: identity)
        XCTAssertFalse(arguments.isEmpty)
        XCTAssertEqual(arguments.count, Int(CommandLine.argc))
        XCTAssertEqual(arguments.first, CommandLine.arguments.first)
        let stale = ProcessIdentity(pid: identity.pid, uid: identity.uid, startSeconds: identity.startSeconds + 1, startMicroseconds: 0)
        XCTAssertTrue(ProcessInspector.arguments(for: stale).isEmpty)
    }

    private let containersJSON = Data("""
    [{"Id":"abc123def456","Names":["/shop-db-1"],"Image":"postgres:16","Ports":[{"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":5433,"Type":"tcp"},{"IP":"::","PrivatePort":5432,"PublicPort":5433,"Type":"tcp"}]},
     {"Id":"fff000","Names":["/shop-web-1"],"Image":"ghcr.io/acme/web:1.2","Ports":[{"PrivatePort":3000,"PublicPort":8080,"Type":"tcp"},{"PrivatePort":53,"PublicPort":5353,"Type":"udp"},{"PrivatePort":9000,"Type":"tcp"}]},
     {"Id":"000aaa","Names":["/internal"],"Image":"busybox","Ports":[]}]
    """.utf8)

    func testContainerListKeepsOnlyPublishedTCPPorts() {
        let containers = Docker.parseContainers(containersJSON)
        XCTAssertEqual(containers.map(\.name), ["shop-db-1", "shop-web-1"])
        XCTAssertEqual(containers[0].ports, [5433])
        XCTAssertEqual(containers[1].ports, [8080])
        XCTAssertEqual(containers[1].imageName, "web:1.2")
        XCTAssertTrue(containers[0].isDatabase)
        XCTAssertFalse(containers[1].isDatabase)
        XCTAssertTrue(Docker.parseContainers(Data("not json".utf8)).isEmpty)
    }

    func testContainerIdentityNamesCategorizesAndLinksTheRow() {
        let containers = Docker.parseContainers(containersJSON)
        let process = ProcessIdentity(pid: 4242, uid: geteuid(), startSeconds: 10, startMicroseconds: 20)
        let details = ProcessDetails(executablePath: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", arguments: ["com.docker.backend", "--token", "x"])
        let database = Listener(process: process, name: "com.docker.backend", port: 5433, addresses: ["::"])
        let web = Listener(process: process, name: "com.docker.backend", port: 8080, addresses: ["::"])
        let databaseService = ServiceIdentity(listener: database, details: details, container: containers[0])
        let webService = ServiceIdentity(listener: web, details: details, container: containers[1])
        XCTAssertEqual(databaseService.category, .database)
        XCTAssertEqual(databaseService.projectName, "shop-db-1")
        XCTAssertNil(databaseService.command)
        XCTAssertNil(databaseService.webURL(for: database))
        XCTAssertEqual(webService.category, .development)
        XCTAssertEqual(webService.webURL(for: web)?.absoluteString, "http://localhost:8080")
        XCTAssertEqual(ServiceIdentity(listener: web, details: details).category, .application)
        XCTAssertTrue(Docker.isProxy("com.docker.backend"))
        XCTAssertTrue(Docker.isProxy("OrbStack Helper"))
        XCTAssertFalse(Docker.isProxy("node"))
    }

    func testEngineRequestsGoThroughTheUnixSocketAndRejectBadIdentifiers() throws {
        let path = "/tmp/yolk-test-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
        defer { unlink(path) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(server) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(server, 4), 0)
        let json = containersJSON
        let requests = RequestLog()
        let thread = Thread {
            for _ in 0..<2 {
                let client = accept(server, nil, nil)
                guard client >= 0 else { return }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = read(client, &buffer, buffer.count)
                let line = String(decoding: buffer[..<max(count, 0)], as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
                requests.append(line)
                var reply = Data((line.hasPrefix("GET") ? "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n" : "HTTP/1.0 204 No Content\r\n\r\n").utf8)
                if line.hasPrefix("GET") { reply.append(json) }
                reply.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
                close(client)
            }
        }
        thread.start()
        XCTAssertEqual(Docker.containers(socketPaths: ["/tmp/yolk-missing.sock", path]).map(\.name), ["shop-db-1", "shop-web-1"])
        XCTAssertTrue(Docker.stop(containerID: "abc123def456", socketPaths: [path]))
        XCTAssertEqual(requests.lines, ["GET /containers/json HTTP/1.0", "POST /containers/abc123def456/stop?t=5 HTTP/1.0"])
        XCTAssertFalse(Docker.stop(containerID: "../../version", socketPaths: [path]))
        XCTAssertFalse(Docker.stop(containerID: "", socketPaths: [path]))
        XCTAssertTrue(Docker.containers(socketPaths: ["/tmp/yolk-missing.sock"]).isEmpty)
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ line: String) { lock.lock(); stored.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}
