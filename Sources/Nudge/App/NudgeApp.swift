import AppKit
import NudgeKit

@main
enum NudgeApp {
    private static var delegate: AppDelegate?

    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot") {
            let path = flag + 1 < arguments.count ? arguments[flag + 1] : "snapshots"
            do {
                try Snapshots.render(to: URL(filePath: path))
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }

        if let flag = arguments.firstIndex(of: "--readme-images") {
            let path = flag + 1 < arguments.count ? arguments[flag + 1] : "docs/images"
            do { try ReadmeImages.render(to: URL(filePath: path)) } catch {
                FileHandle.standardError.write(Data("readme images failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }
        if let flag = arguments.firstIndex(of: "--icon") {
            let path = flag + 1 < arguments.count ? arguments[flag + 1] : "AppIcon.iconset"
            do { try AppIconView.writeIconset(to: URL(filePath: path)) } catch {
                FileHandle.standardError.write(Data("icon failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }
        if arguments.contains("--dump-sessions") { return dumpSessions() }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        // Also set in Info.plist (LSUIElement); this covers `swift run`.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// `Nudge --dump-sessions`: prints what Nudge currently sees, then exits. Reads only.
    private static func dumpSessions() {
        let service = ObservationService()
        service.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        for target in HookSetup.availableTargets {
            print("\(target.agent.productName) hooks: \(HookInstaller(target: target).status(bundledCollector: HookSetup.bundledCollector))")
        }
        for session in service.sessions {
            let fields = [session.project, session.agent.productName, "\(session.kind)", session.host.displayName, session.location, session.branch,
                          session.task, session.activity, session.quote,
                          session.choices.isEmpty ? nil : "choices: " + session.choices.joined(separator: " / ")].compactMap { $0 }
            print("- " + fields.joined(separator: " | "))
        }
        if service.sessions.isEmpty { print("(no sessions)") }
        service.stop()
    }
}
