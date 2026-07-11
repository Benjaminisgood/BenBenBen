import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Off"
    @Published private(set) var lastError: String?

    private let service = SMAppService.loginItem(
        identifier: "io.github.benjaminisgood.benbenben.login-helper"
    )

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusText = "Enabled"
        case .requiresApproval:
            isEnabled = false
            statusText = "Needs approval in System Settings"
        case .notFound:
            isEnabled = false
            statusText = "Helper is available in the packaged app"
        case .notRegistered:
            isEnabled = false
            statusText = "Off"
        @unknown default:
            isEnabled = false
            statusText = "Unknown"
        }
    }
}
