import XCTest
import Foundation
import Darwin
@testable import LocalPortsCore

final class LocalPortsCoreTests: XCTestCase {
    private let example = ProcessIdentity(pid: 4242, uid: geteuid(), startSeconds: 10, startMicroseconds: 20)

    func testMergesIPv4AndIPv6WithoutMergingDifferentProcesses() {
        let other = ProcessIdentity(pid: 4243, uid: geteuid(), startSeconds: 10, startMicroseconds: 20)
        let result = Listener.merged([
            Listener(process: example, name: "node", port: 5173, addresses: ["127.0.0.1"]),
            Listener(process: example, name: "node", port: 5173, addresses: ["::1"]),
            Listener(process: other, name: "node", port: 5173, addresses: ["::1"])
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.addresses, ["127.0.0.1", "::1"])
    }

    func testBrowserHintsAndLoopbackAliases() {
        XCTAssertEqual(listener("node", 5173).suggestedWebURL?.absoluteString, "http://localhost:5173")
        XCTAssertEqual(listener("caddy", 8443).suggestedWebURL?.scheme, "https")
        XCTAssertNil(listener("redis-server", 6379).suggestedWebURL)
        XCTAssertNil(listener("mysqld", 3306).suggestedWebURL)
        XCTAssertNil(listener("ControlCenter", 5000).suggestedWebURL)
        XCTAssertNil(listener("node", 9229).suggestedWebURL)
        XCTAssertNil(listener("unknown", 49152).suggestedWebURL)
        let alias = Listener(process: example, name: "node", port: 3000, addresses: ["127.0.0.2"])
        XCTAssertEqual(alias.httpURL.absoluteString, "http://127.0.0.2:3000")
    }

    func testNativeScannerFindsIPv4Loopback() throws {
        let fixture = try SocketFixture(address: "127.0.0.1")
        let result = try ownListeners(port: fixture.port)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.addresses, ["127.0.0.1"])
    }

    func testNativeScannerFindsWildcardAndIPv6() throws {
        let wildcard = try SocketFixture(address: "0.0.0.0")
        let ipv6 = try SocketFixture(address: "::1")
        let wildcard6 = try SocketFixture(address: "::")
        XCTAssertEqual(try ownListeners(port: wildcard.port).first?.addresses, ["0.0.0.0"])
        XCTAssertEqual(try ownListeners(port: ipv6.port).first?.addresses, ["::1"])
        XCTAssertEqual(try ownListeners(port: wildcard6.port).first?.addresses, ["::"])
    }

    func testNativeScannerDeduplicatesDualStack() throws {
        let ipv4 = try SocketFixture(address: "127.0.0.1")
        let ipv6 = try SocketFixture(address: "::1", port: ipv4.port)
        let result = try ownListeners(port: ipv6.port)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.addresses, ["127.0.0.1", "::1"])
    }

    func testBoundUDPAndNonListeningTCPAreExcluded() throws {
        let udp = try SocketFixture(address: "127.0.0.1", udp: true)
        let tcp = try SocketFixture(address: "127.0.0.1", listening: false)
        XCTAssertTrue(try ownListeners(port: udp.port).isEmpty)
        XCTAssertTrue(try ownListeners(port: tcp.port).isEmpty)
    }

    func testNormalTerminationRemovesRealListener() throws {
        let fixture = try ChildFixture(ignoreTerm: false)
        XCTAssertTrue(try ProcessInspector.scan().contains { $0.process == fixture.identity && $0.port == fixture.port })
        try ProcessInspector.terminate(fixture.identity)
        XCTAssertTrue(waitUntil { !fixture.process.isRunning })
        XCTAssertFalse(try ProcessInspector.scan().contains { $0.process == fixture.identity })
    }

    func testForceTerminationAfterIgnoredNormalSignal() throws {
        let fixture = try ChildFixture(ignoreTerm: true)
        try ProcessInspector.terminate(fixture.identity)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertTrue(fixture.process.isRunning)
        XCTAssertTrue(ProcessInspector.isRunning(fixture.identity))
        try ProcessInspector.terminate(fixture.identity, force: true)
        XCTAssertTrue(waitUntil { !fixture.process.isRunning })
    }

    func testStaleIdentityCannotSignalAReusedPID() throws {
        let fixture = try ChildFixture(ignoreTerm: false)
        let actual = fixture.identity
        let stale = ProcessIdentity(pid: actual.pid, uid: actual.uid,
                                    startSeconds: actual.startSeconds + 1, startMicroseconds: actual.startMicroseconds)
        XCTAssertThrowsError(try ProcessInspector.terminate(stale)) {
            XCTAssertEqual(($0 as? InspectionError)?.code, ESTALE)
        }
        XCTAssertTrue(fixture.process.isRunning)
    }

    func testRefusesOwnProcessAndOtherUsers() throws {
        let current = try ProcessInspector.identity(pid: getpid())
        XCTAssertFalse(current.canTerminate)
        XCTAssertThrowsError(try ProcessInspector.terminate(current)) {
            XCTAssertEqual(($0 as? InspectionError)?.code, EPERM)
        }
        let otherUser = ProcessIdentity(pid: 4242, uid: geteuid() + 1, startSeconds: 1, startMicroseconds: 1)
        XCTAssertFalse(otherUser.canTerminate)
        XCTAssertThrowsError(try ProcessInspector.terminate(otherUser))
    }

    private func listener(_ name: String, _ port: UInt16) -> Listener {
        Listener(process: example, name: name, port: port, addresses: ["127.0.0.1"])
    }

    private func ownListeners(port: UInt16) throws -> [Listener] {
        try ProcessInspector.scan().filter { $0.process.pid == getpid() && $0.port == port }
    }

    private func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return predicate()
    }
}

private final class SocketFixture {
    let fd: Int32
    let port: UInt16

    init(address: String, port: UInt16 = 0, udp: Bool = false, listening: Bool = true) throws {
        let ipv6 = address.contains(":")
        let descriptor = socket(ipv6 ? AF_INET6 : AF_INET, udp ? SOCK_DGRAM : SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        do {
            var storage = sockaddr_storage()
            var size: socklen_t
            if ipv6 {
                var only: Int32 = 1
                setsockopt(descriptor, IPPROTO_IPV6, IPV6_V6ONLY, &only, socklen_t(MemoryLayout.size(ofValue: only)))
                var socketAddress = sockaddr_in6()
                socketAddress.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                socketAddress.sin6_family = sa_family_t(AF_INET6)
                socketAddress.sin6_port = port.bigEndian
                inet_pton(AF_INET6, address, &socketAddress.sin6_addr)
                size = socklen_t(MemoryLayout.size(ofValue: socketAddress))
                withUnsafePointer(to: &socketAddress) { pointer in
                    withUnsafeMutablePointer(to: &storage) { destination in
                        _ = memcpy(destination, pointer, Int(size))
                    }
                }
            } else {
                var socketAddress = sockaddr_in()
                socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                socketAddress.sin_family = sa_family_t(AF_INET)
                socketAddress.sin_port = port.bigEndian
                inet_pton(AF_INET, address, &socketAddress.sin_addr)
                size = socklen_t(MemoryLayout.size(ofValue: socketAddress))
                withUnsafePointer(to: &socketAddress) { pointer in
                    withUnsafeMutablePointer(to: &storage) { destination in
                        _ = memcpy(destination, pointer, Int(size))
                    }
                }
            }
            let bound = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, size) }
            }
            guard bound == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if !udp && listening {
                guard Darwin.listen(descriptor, 4) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            }
            let named = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
            }
            guard named == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            self.port = withUnsafePointer(to: &storage) {
                // The port occupies the same offset in sockaddr_in and sockaddr_in6.
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
            }
            self.fd = descriptor
        } catch { close(descriptor); throw error }
    }

    deinit { close(fd) }
}

private final class ChildFixture {
    let process: Process
    let identity: ProcessIdentity
    let port: UInt16

    init(ignoreTerm: Bool) throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-u", "-c", """
        import signal, socket, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN if \(ignoreTerm ? "True" : "False") else signal.SIG_DFL)
        server = socket.socket()
        server.bind(('127.0.0.1', 0))
        server.listen()
        print(server.getsockname()[1], flush=True)
        time.sleep(60)
        """]
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        let ready = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(ready) else {
            child.terminate()
            throw NSError(domain: "Fixture did not start", code: 1)
        }
        self.process = child
        self.port = port
        self.identity = try ProcessInspector.identity(pid: child.processIdentifier)
    }

    deinit {
        if process.isRunning { try? ProcessInspector.terminate(identity, force: true) }
        // Foundation reaps this child asynchronously. Waiting here can deadlock
        // when an async XCTest resumes on a different thread from Process.run().
    }
}
