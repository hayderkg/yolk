import AppKit
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isUpdating = false
    @Published var error: String?
    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        let service = service ?? SystemLoginItemService()
        self.service = service
        self.status = service.status
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false; refresh() }
        do {
            if enabled { try service.register() }
            else { try await service.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change launch at login. \(error.localizedDescription)"
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
