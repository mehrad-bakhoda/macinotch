import AppKit
import Foundation

enum SessionLauncher {
    static func binary(for provider: NotchSource) -> String? {
        let name = provider == .claude ? "claude" : "codex"
        let direct = ["/opt/homebrew/bin/", "/usr/local/bin/",
                      NSHomeDirectory() + "/.local/bin/",
                      NSHomeDirectory() + "/.claude/local/"]
        for base in direct where FileManager.default.isExecutableFile(atPath: base + name) {
            return base + name
        }

        guard provider != .claude else { return nil }
        for bundle in ["com.openai.codex", "com.openai.chat"] {
            guard let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundle) else { continue }
            let path = url.appendingPathComponent("Contents/Resources/codex").path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func canResume(_ session: CodeSession) -> Bool {
        binary(for: session.provider) != nil
    }

    @discardableResult
    static func resume(_ session: CodeSession) -> Bool {
        guard let tool = binary(for: session.provider) else { return false }

        let directory = session.project.hasPrefix("/")
            ? session.project : NSHomeDirectory()
        let flag = session.provider == .claude ? "--resume" : "resume"
        let command = "cd \(quoted(directory)) && \(quoted(tool)) \(flag) \(session.id)"
        return runInTerminal(command)
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runInTerminal(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
