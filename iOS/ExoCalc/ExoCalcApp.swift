import SwiftUI
import ExoCalcCore

@main
struct ExoCalcApp: App {
    @StateObject private var model = CalcModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { p in
                    if p == .active { model.refreshRatesIfNeeded() }
                    if p == .background { model.save() }
                }
        }
    }
}

enum Theme {
    static let bg = UIColor(red: 0.125, green: 0.13, blue: 0.14, alpha: 1)
    static let text = UIColor(white: 0.88, alpha: 1)
    static let number = UIColor(white: 0.98, alpha: 1)
    static let unit = UIColor(red: 0.56, green: 0.76, blue: 0.95, alpha: 1)
    static let keyword = UIColor(red: 0.78, green: 0.62, blue: 0.95, alpha: 1)
    static let function = UIColor(red: 0.95, green: 0.76, blue: 0.47, alpha: 1)
    static let variable = UIColor(red: 0.95, green: 0.62, blue: 0.62, alpha: 1)
    static let comment = UIColor(white: 0.46, alpha: 1)
    static let result = UIColor(red: 0.6, green: 0.84, blue: 0.24, alpha: 1)
    static let hint = UIColor(red: 0.92, green: 0.5, blue: 0.4, alpha: 0.9)
    static let status = UIColor(white: 0.55, alpha: 1)

    static func color(_ k: HKind) -> UIColor {
        switch k {
        case .number: return number
        case .unit: return unit
        case .keyword: return keyword
        case .function: return function
        case .variable: return variable
        case .comment, .label: return comment
        case .error: return hint
        }
    }
}
