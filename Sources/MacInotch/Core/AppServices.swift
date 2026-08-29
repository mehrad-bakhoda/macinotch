import Foundation

@MainActor
enum AppServices {
    static weak var bridge: NotificationBridge?

    static var bridgeStatusText: String {
        switch bridge?.status ?? .off {
        case .off:                 return "off"
        case .running:             return "running"
        case .needsFullDiskAccess: return "needs-full-disk-access"
        case .unavailable(let m):  return "unavailable: \(m)"
        }
    }
}
