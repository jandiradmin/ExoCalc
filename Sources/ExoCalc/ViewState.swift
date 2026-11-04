import AppKit
import Combine
import ServiceManagement

// Local UI state lives in ObservableObject classes instead of @State:
// in the macOS 27 SDK @State is a macro whose plugin ships only with full Xcode,
// so Command Line Tools builds fail on it.

final class SettingsUIState: ObservableObject {
    static let shared = SettingsUIState()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

final class RecorderState: ObservableObject {
    static let shared = RecorderState()
    @Published var recording = false
    var monitor: Any?
}

final class HistoryUIState: ObservableObject {
    @Published var query = ""
    @Published var selection = Set<UUID>()
}
