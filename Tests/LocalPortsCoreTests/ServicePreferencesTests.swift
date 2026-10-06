import XCTest
import LocalPortsCore

final class ServicePreferencesTests: XCTestCase {
    private func listener(pid: Int32 = 100, port: UInt16 = 5173, addresses: Set<String> = ["127.0.0.1"]) -> Listener {
        Listener(process: ProcessIdentity(pid: pid, uid: 501, startSeconds: UInt64(pid), startMicroseconds: 0),
                 name: "node", port: port, addresses: addresses)
    }
    private func service(_ listener: Listener, path: String = "/tmp/portfolio") -> ServiceIdentity {
        ServiceIdentity(listener: listener, details: ProcessDetails(executablePath: "/usr/local/bin/node", workingDirectory: path), readProject: false)
    }

    func testFavoritesSurviveNewPIDAndSerialization() {
        let old = listener(), restarted = listener(pid: 200)
        var prefs = ServicePreferences()
        prefs.toggleFavorite(old, service: service(old))
        let restored = ServicePreferences(data: prefs.data)
        XCTAssertTrue(restored.isFavorite(restarted, service: service(restarted)))
    }

    func testPreferencesDoNotLeakBetweenProjectsOrPorts() {
        let first = listener(), otherPort = listener(port: 5174)
        var prefs = ServicePreferences()
        prefs.toggleHidden(first, service: service(first))
        XCTAssertFalse(prefs.isHidden(first, service: service(first, path: "/tmp/another-project")))
        XCTAssertFalse(prefs.isHidden(otherPort, service: service(otherPort)))
    }

    func testRestoringHiddenPreservesFavorites() {
        let first = listener()
        var prefs = ServicePreferences()
        prefs.toggleFavorite(first, service: service(first))
        prefs.toggleHidden(first, service: service(first))
        XCTAssertTrue(prefs.isHidden(first, service: service(first)))
        prefs.restoreAllHidden()
        XCTAssertFalse(prefs.isHidden(first, service: service(first)))
        XCTAssertTrue(prefs.isFavorite(first, service: service(first)))
    }

    func testInvalidStoredDataDoesNotBreakLaunch() {
        XCTAssertEqual(ServicePreferences(data: Data("invalid".utf8)), ServicePreferences())
    }

    func testSearchMatchesProjectRuntimePortAndPID() {
        let first = listener(pid: 12345)
        let second = listener(pid: 200, port: 8000)
        let services = [first.id: service(first, path: "/tmp/Árbol-web"), second.id: service(second, path: "/tmp/api")]
        for query in ["ARBOL", "node 5173", "12345", "arbol node"] {
            XCTAssertEqual(ServiceList.filtered([first, second], services: services, preferences: ServicePreferences(), query: query).map(\.id), [first.id])
        }
        XCTAssertTrue(ServiceList.filtered([first], services: services, preferences: ServicePreferences(), query: "missing").isEmpty)
    }

    func testHiddenAndFavoriteFiltersCombine() {
        let first = listener(), second = listener(pid: 200, port: 8000)
        let services = [first.id: service(first), second.id: service(second)]
        var prefs = ServicePreferences()
        prefs.toggleFavorite(first, service: services[first.id]!)
        prefs.toggleHidden(first, service: services[first.id]!)
        XCTAssertEqual(ServiceList.filtered([first, second], services: services, preferences: prefs).map(\.id), [second.id])
        XCTAssertTrue(ServiceList.filtered([first, second], services: services, preferences: prefs, favoritesOnly: true).isEmpty)
        XCTAssertEqual(ServiceList.filtered([first, second], services: services, preferences: prefs, favoritesOnly: true, showHidden: true).map(\.id), [first.id])
    }

    func testFavoritesSortBeforeLowerPorts() {
        let first = listener(port: 3000), second = listener(pid: 200, port: 8000)
        let services = [first.id: service(first), second.id: service(second)]
        var prefs = ServicePreferences()
        prefs.toggleFavorite(second, service: services[second.id]!)
        XCTAssertEqual(ServiceList.filtered([first, second], services: services, preferences: prefs).map(\.id), [second.id, first.id])
    }

    func testNetworkScopeIncludesEitherWildcard() {
        XCTAssertFalse(listener(addresses: ["127.0.0.1", "::1"]).listensOnAllInterfaces)
        XCTAssertFalse(listener(addresses: ["127.0.0.2"]).listensOnAllInterfaces)
        XCTAssertTrue(listener(addresses: ["::"]).listensOnAllInterfaces)
        XCTAssertTrue(listener(addresses: ["0.0.0.0", "::1"]).listensOnAllInterfaces)
    }
}
