import Foundation

enum PluginInstallPhase: Equatable {
    case downloading(progress: Double)
    case installing
    case uninstalling
    case failed(messageKey: String)

    var isBusy: Bool {
        switch self {
        case .failed: false
        default: true
        }
    }
}
