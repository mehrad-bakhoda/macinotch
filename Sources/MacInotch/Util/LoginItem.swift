import Foundation
import AppKit

enum LoginItem {
    static let label = "io.macinotch.agent"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func set(_ on: Bool) { on ? enable() : disable() }

    private static func enable() {
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: plistURL)
        run(["launchctl", "bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func disable() {
        run(["launchctl", "bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = Array(args.dropFirst())
        try? p.run()
        p.waitUntilExit()
    }
}
