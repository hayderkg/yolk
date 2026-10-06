import Foundation
import Darwin
import PortInspector

public struct InspectionError: LocalizedError, Sendable {
    public let code: Int32
    public var errorDescription: String? {
        switch code {
        case ESRCH: return "The process has already exited."
        case ESTALE: return "The process has changed. Refresh the list and try again."
        case EPERM, EACCES: return "macOS doesn't let your user access this process."
        default: return String(cString: strerror(code))
        }
    }
}

public enum ProcessInspector {
    public static func scan() throws -> [Listener] {
        let snapshot = lp_scan()
        defer { lp_free_scan(snapshot) }
        guard snapshot.error_code == 0 else { throw InspectionError(code: snapshot.error_code) }
        guard let items = snapshot.items else { return [] }
        let listeners = UnsafeBufferPointer(start: items, count: snapshot.count).map { item in
            var name = item.name
            var address = item.address
            let processName = withUnsafePointer(to: &name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            let bindAddress = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: CChar.self, capacity: 46) { String(cString: $0) }
            }
            return Listener(process: ProcessIdentity(item.identity), name: processName,
                            port: item.port, addresses: [bindAddress])
        }
        return Listener.merged(listeners)
    }

    public static func identity(pid: Int32) throws -> ProcessIdentity {
        var identity = LPIdentity()
        let result = lp_identity(pid, &identity)
        guard result == 0 else { throw InspectionError(code: result) }
        return ProcessIdentity(identity)
    }

    public static func isRunning(_ identity: ProcessIdentity) -> Bool {
        (try? self.identity(pid: identity.pid)) == identity
    }

    public static func details(for identity: ProcessIdentity) -> ProcessDetails? {
        var details = LPDetails()
        guard lp_details(identity.native, &details) == 0 else { return nil }
        let executable = withUnsafeBytes(of: details.executable) {
            String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let directory = withUnsafeBytes(of: details.working_directory) {
            String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return ProcessDetails(executablePath: executable, workingDirectory: directory, arguments: arguments(for: identity))
    }

    /// Reads argv through `KERN_PROCARGS2`; empty for processes this user may not inspect.
    public static func arguments(for identity: ProcessIdentity) -> [String] {
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, identity.pid]
        var size = 0
        guard sysctl(&name, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size,
              isRunning(identity) else { return [] }
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0 else { return [] }
        var index = MemoryLayout<Int32>.size
        // Layout: argc, executable path, NUL padding, then argc NUL-terminated arguments.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var result: [String] = []
        while index < size, result.count < min(Int(count), 64) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }

    public static func terminate(_ identity: ProcessIdentity, force: Bool = false) throws {
        let result = lp_signal(identity.native, force ? SIGKILL : SIGTERM)
        guard result == 0 else { throw InspectionError(code: result) }
    }
}

private extension ProcessIdentity {
    init(_ native: LPIdentity) {
        self.init(pid: native.pid, uid: native.uid, startSeconds: native.start_seconds,
                  startMicroseconds: native.start_microseconds)
    }

    var native: LPIdentity {
        LPIdentity(pid: pid, uid: uid, start_seconds: startSeconds, start_microseconds: startMicroseconds)
    }
}
