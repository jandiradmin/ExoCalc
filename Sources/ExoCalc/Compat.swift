import AppKit
import SwiftUI
import ServiceManagement

/// Launch at login: SMAppService exists only on macOS 13+.
enum LoginItem {
    static var supported: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func set(_ on: Bool) -> Bool {
        guard #available(macOS 13, *) else { return false }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}

extension View {
    /// Grouped form style on macOS 13+, plain padded form on older systems.
    @ViewBuilder func groupedForm() -> some View {
        if #available(macOS 13, *) {
            self.formStyle(.grouped)
        } else {
            self.padding(20)
        }
    }
}
