import XCTest
import Foundation
import Darwin
@testable import LocalPortsCore

final class ServiceIdentityTests: XCTestCase {
    private let process = ProcessIdentity(pid: 4242, uid: geteuid(), startSeconds: 10, startMicroseconds: 20)
    private func listener(_ name: String, port: UInt16 = 49152) -> Listener {
        Listener(process: process, name: name, port: port, addresses: ["127.0.0.1"])
    }

    func testCategoriesPreferRealAppsAndKnownServicesOverPorts() {
        XCTAssertEqual(ServiceIdentity.category(for: listener("node")), .development)
        XCTAssertEqual(ServiceIdentity.category(for: listener("redis-server", port: 3000)), .database)
        XCTAssertEqual(ServiceIdentity.category(for: listener("mysqld")), .database)
        XCTAssertEqual(ServiceIdentity.category(for: listener("ControlCenter", port: 5000)), .system)
        XCTAssertEqual(ServiceIdentity.category(for: listener("Raycast"), details: ProcessDetails(executablePath: "/Applications/Raycast.app/Contents/MacOS/Raycast")), .application)
        XCTAssertEqual(ServiceIdentity.category(for: listener("node"), details: ProcessDetails(executablePath: "/Applications/Example.app/Contents/Helpers/node")), .application)
        XCTAssertEqual(ServiceIdentity.category(for: listener("unknown")), .other)
    }

    func testNativeDetailsKeepExecutableAndWorkingDirectory() throws {
        let identity = try ProcessInspector.identity(pid: getpid())
        let details = try XCTUnwrap(ProcessInspector.details(for: identity))
        XCTAssertTrue(details.executablePath.hasPrefix("/"))
        XCTAssertTrue(details.workingDirectory.hasPrefix("/"))
    }

    func testFindsProjectNameFromParentPackage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"name":"@studio/site","version":"1.0.0"}"#.utf8).write(to: directory.appendingPathComponent("package.json"))
        let service = ServiceIdentity(listener: listener("node"), details: ProcessDetails(workingDirectory: directory.appendingPathComponent("src").path))
        XCTAssertEqual(service.projectName, "@studio/site")
        XCTAssertEqual(service.projectDirectory?.path, directory.path)
    }

    func testFallsBackToFolderWithoutInventingAProjectForApps() {
        let details = ProcessDetails(workingDirectory: "/tmp/example-project")
        XCTAssertEqual(ServiceIdentity(listener: listener("node"), details: details, readProject: false).projectName, "example-project")
        XCTAssertNil(ServiceIdentity(listener: listener("ControlCenter"), details: details).projectName)
        XCTAssertNil(ServiceIdentity(listener: listener("node"), details: ProcessDetails(workingDirectory: "/")).projectName)
    }

    func testInitialsAndOwningBundle() {
        XCTAssertEqual(ServiceIdentity.initials(for: "node"), "NO")
        XCTAssertEqual(ServiceIdentity.initials(for: "redis-server"), "RS")
        XCTAssertEqual(ServiceIdentity.initials(for: ""), "?")
        XCTAssertEqual(ServiceIdentity.initials(for: "árbol verde"), "ÁV")
        let details = ProcessDetails(executablePath: "/Applications/Example.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper")
        XCTAssertEqual(details.appBundleURL?.path, "/Applications/Example.app")
    }

    func testIconLinksRespectSameLocalOrigin() throws {
        let origin = try XCTUnwrap(URL(string: "http://localhost:5173"))
        let html = #"""
        <link href="/brand.png?a=1&amp;b=2" type="image/png" rel="shortcut icon">
        <link rel='apple-touch-icon' href='/touch.png'>
        <link rel=icon href=/small.ico>
        <link rel="icon" href="https://remote.example/logo.png">
        <link rel="icon" href="http://localhost:1234/other.png">
        """#
        XCTAssertEqual(FaviconPolicy.iconURLs(in: html, origin: origin).map(\.absoluteString), [
            "http://localhost:5173/brand.png?a=1&b=2", "http://localhost:5173/touch.png", "http://localhost:5173/small.ico"
        ])
        XCTAssertFalse(FaviconPolicy.sameOrigin(URL(string: "http://127.0.0.1:5173/icon.png")!, origin))
        XCTAssertFalse(FaviconPolicy.isLocal(URL(string: "http://localhost.evil.example:5173")!))
        XCTAssertFalse(FaviconPolicy.isLocal(URL(string: "http://user:password@localhost:5173")!))
        XCTAssertTrue(FaviconPolicy.isLocal(URL(string: "http://[::1]:5173")!))
        XCTAssertTrue(FaviconPolicy.isLocal(URL(string: "http://127.0.0.2:5173")!))
    }

    func testSVGAllowsSelfContainedArtworkAndRejectsExternalResources() {
        XCTAssertTrue(FaviconPolicy.isSelfContainedSVG(Data(#"<svg xmlns="http://www.w3.org/2000/svg"><style>path {fill: black}</style><path d="M0 0L10 10"/></svg>"#.utf8)))
        XCTAssertFalse(FaviconPolicy.isSelfContainedSVG(Data(#"<svg><image href="https://remote.example/icon.png"/></svg>"#.utf8)))
        XCTAssertFalse(FaviconPolicy.isSelfContainedSVG(Data(#"<svg><style>path {fill:url(https://remote.example/x)}</style></svg>"#.utf8)))
        XCTAssertFalse(FaviconPolicy.isSelfContainedSVG(Data(#"<svg><use href="&#104;ttps://remote.example/x"/></svg>"#.utf8)))
        XCTAssertFalse(FaviconPolicy.isSelfContainedSVG(Data("<html>not an icon</html>".utf8)))
    }

    func testFetchesHTMLLinkedLocalFavicon() async throws {
        let fixture = try FaviconServer(mode: "linked")
        let data = await LocalFavicon.load(from: fixture.url)
        XCTAssertEqual(Array(try XCTUnwrap(data).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    func testRejectsRedirectsToOtherPorts() async throws {
        let fixture = try FaviconServer(mode: "redirect")
        let data = await LocalFavicon.load(from: fixture.url)
        XCTAssertNil(data)
        let (count, _) = try await URLSession.shared.data(from: fixture.url.appendingPathComponent("count"))
        XCTAssertEqual(String(decoding: count, as: UTF8.self), "0")
    }

    func testRejectsOversizedImages() async throws {
        let fixture = try FaviconServer(mode: "oversized")
        let data = await LocalFavicon.load(from: fixture.url)
        XCTAssertNil(data)
    }
}

private final class FaviconServer {
    let process: Process
    let identity: ProcessIdentity
    let url: URL

    init(mode: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", #"""
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import base64, threading, sys
        mode = sys.argv[1]
        hits = 0
        png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=')
        class Trap(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_GET(self):
                global hits
                hits += 1
                self.send_response(200); self.end_headers(); self.wfile.write(png)
        trap = ThreadingHTTPServer(('127.0.0.1', 0), Trap)
        threading.Thread(target=trap.serve_forever, daemon=True).start()
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_GET(self):
                if self.path == '/count':
                    body = str(hits).encode(); kind = 'text/plain'
                elif self.path == '/favicon.ico' and mode == 'redirect':
                    self.send_response(302)
                    self.send_header('Location', 'http://127.0.0.1:%d/probe' % trap.server_port)
                    self.end_headers(); return
                elif self.path == '/favicon.ico' and mode == 'oversized':
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/png')
                    self.send_header('Content-Length', '9000000')
                    self.end_headers(); return
                elif self.path == '/' and mode == 'linked':
                    body = b'<html><head><link href="/brand.png" rel="icon"></head></html>'; kind = 'text/html'
                elif self.path == '/brand.png' and mode == 'linked':
                    body = png; kind = 'image/png'
                else:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200)
                self.send_header('Content-Type', kind)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body)
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_port, flush=True)
        server.serve_forever()
        """#, mode]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let ready = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(ready), let url = URL(string: "http://127.0.0.1:\(port)") else {
            process.terminate()
            throw NSError(domain: "Favicon fixture failed", code: 1)
        }
        self.process = process
        self.url = url
        self.identity = try ProcessInspector.identity(pid: process.processIdentifier)
    }

    deinit {
        if process.isRunning { try? ProcessInspector.terminate(identity, force: true) }
        // Foundation reaps this child asynchronously. Waiting here can deadlock
        // when an async XCTest resumes on a different thread from Process.run().
    }
}
