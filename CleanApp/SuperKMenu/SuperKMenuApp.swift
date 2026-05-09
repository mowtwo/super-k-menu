import AppKit
import SwiftUI

@main
struct SuperKMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private lazy var actionRouter = ActionRouter(configStore: configStore)
    private var statusItem: NSStatusItem?
    private var windowController: NSWindowController?
    private var launchedByActionURL = false
    private var initialWindowWorkItem: DispatchWorkItem?
    private var isCleaningUpForQuit = false
    private var lastHandledURL: URL?
    private var lastHandledURLDate: Date?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configStore.bootstrapIfNeeded()
        SystemActions.enableFinderExtension()
        setupStatusItem()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            if !self.launchedByActionURL {
                self.showConfigurationWindow()
            }
        }
        initialWindowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handle(urls)
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL) else {
            DebugLog.append("received malformed apple event url")
            return
        }
        handle([url])
    }

    private func handle(_ urls: [URL]) {
        launchedByActionURL = true
        initialWindowWorkItem?.cancel()
        initialWindowWorkItem = nil
        for url in urls {
            if shouldSkipDuplicate(url) {
                DebugLog.append("skipped duplicate url=\(url.absoluteString)")
                continue
            }
            DebugLog.append("handling url=\(url.absoluteString)")
            if url.scheme == "superkmenu", url.host == "settings" {
                showConfigurationWindow()
            } else {
                actionRouter.handle(url)
            }
        }
    }

    private func shouldSkipDuplicate(_ url: URL) -> Bool {
        defer {
            lastHandledURL = url
            lastHandledURLDate = Date()
        }
        guard lastHandledURL == url,
              let lastHandledURLDate,
              Date().timeIntervalSince(lastHandledURLDate) < 1 else {
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConfigurationWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanupFinderMenuBeforeQuit()
        return .terminateNow
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusBarIcon.image(configStore: configStore)
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(statusMenuItem(title: "Open SuperKMenu", action: #selector(openConfigurationFromMenu), icon: "slider.horizontal.3"))
        menu.addItem(statusMenuItem(title: "View Logs", action: #selector(openLogsFromMenu), icon: "doc.text.magnifyingglass"))
        menu.addItem(statusMenuItem(title: "Report Issue with Logs", action: #selector(reportIssueFromMenu), icon: "ladybug"))
        menu.addItem(.separator())
        menu.addItem(statusMenuItem(title: "Open Extension Settings", action: #selector(openExtensionSettingsFromMenu), icon: "puzzlepiece.extension"))
        menu.addItem(statusMenuItem(title: "Restart Finder", action: #selector(restartFinderFromMenu), icon: "arrow.clockwise"))
        menu.addItem(.separator())
        menu.addItem(statusMenuItem(title: "Quit SuperKMenu", action: #selector(quitFromMenu), icon: "power", keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func statusMenuItem(title: String, action: Selector, icon: String, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        item.image?.size = NSSize(width: 16, height: 16)
        return item
    }

    @objc private func openConfigurationFromMenu() {
        showConfigurationWindow()
    }

    @objc private func openLogsFromMenu() {
        LogWindowPresenter.show()
    }

    @objc private func reportIssueFromMenu() {
        GitHubIssueReporter.openIssue()
    }

    @objc private func openExtensionSettingsFromMenu() {
        SystemActions.openExtensionSettings()
    }

    @objc private func restartFinderFromMenu() {
        SystemActions.restartFinder()
    }

    @objc private func quitFromMenu() {
        cleanupFinderMenuBeforeQuit()
        NSApp.terminate(nil)
    }

    private func cleanupFinderMenuBeforeQuit() {
        guard !isCleaningUpForQuit else {
            return
        }
        isCleaningUpForQuit = true
        SystemActions.disableFinderExtension()
        SystemActions.restartFinder()
    }

    private func showConfigurationWindow() {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ContentView(configStore: configStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperKMenu"
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @ObservedObject var configStore: ConfigStore
    @State private var selectedActionID: String?
    @State private var status = "Enable the actions you want, then restart Finder."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actionList
            editor
            footer
        }
        .padding(24)
        .onAppear {
            configStore.load()
            selectedActionID = configStore.actions.first?.id
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SuperKMenu")
                    .font(.title.weight(.semibold))
                Text("Finder context menu actions")
                    .foregroundStyle(.secondary)
                TextField("Status bar icon path (optional)", text: $configStore.statusBarIconPath.orEmpty)
                    .frame(width: 320)
                    .onSubmit {
                        configStore.save()
                    }
            }
            Spacer()
            Button("Open Extension Settings") {
                SystemActions.openExtensionSettings()
            }
            Button("View Logs") {
                LogWindowPresenter.show()
            }
            Button("Report Issue") {
                GitHubIssueReporter.openIssue()
            }
            Button("Restart Finder") {
                SystemActions.restartFinder()
                status = "Finder restarted."
            }
        }
    }

    private var actionList: some View {
        Table(configStore.actions, selection: $selectedActionID) {
            TableColumn("Enabled") { action in
                Toggle("", isOn: binding(for: action.id).enabled)
                    .labelsHidden()
            }
            .width(70)

            TableColumn("Menu Title") { action in
                Text(action.title)
            }

            TableColumn("Command") { action in
                Text(action.command)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 210)
    }

    private var editor: some View {
        Group {
            if let action = selectedBinding {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enabled in Finder menu", isOn: action.enabled)
                    TextField("Menu title", text: action.title)
                    TextField("Shell command", text: action.command)
                    TextField("Icon path or SF Symbol, e.g. sf:terminal (optional)", text: action.iconPath.orEmpty)
                    Text("Use {path} for the current folder path. Commands run through /bin/zsh -lc.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select an action to edit.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Add Action") {
                let action = MenuAction(title: "New Action", command: "open {path}", enabled: false)
                configStore.actions.append(action)
                selectedActionID = action.id
                configStore.save()
                status = "Action added."
            }

            Button("Remove") {
                guard let selectedActionID else {
                    return
                }
                configStore.actions.removeAll { $0.id == selectedActionID }
                self.selectedActionID = configStore.actions.first?.id
                configStore.save()
                status = "Action removed."
            }
            .disabled(selectedActionID == nil)

            Button("Add Missing Examples") {
                configStore.addMissingExamples()
                selectedActionID = configStore.actions.first?.id
                status = "Missing examples added. Existing actions were kept."
            }

            Spacer()

            Text(status)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Save") {
                configStore.save()
                status = "Saved. Restart Finder if the menu is already open."
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var selectedBinding: Binding<MenuAction>? {
        guard let selectedActionID,
              let index = configStore.actions.firstIndex(where: { $0.id == selectedActionID }) else {
            return nil
        }
        return Binding(
            get: { configStore.actions[index] },
            set: { newValue in
                configStore.actions[index] = newValue
                configStore.save()
            }
        )
    }

    private func binding(for id: String) -> Binding<MenuAction> {
        Binding(
            get: { configStore.actions.first(where: { $0.id == id }) ?? MenuAction(title: "", command: "", enabled: false) },
            set: { newValue in
                guard let index = configStore.actions.firstIndex(where: { $0.id == id }) else {
                    return
                }
                configStore.actions[index] = newValue
                configStore.save()
            }
        )
    }
}

struct MenuAction: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var command: String
    var enabled: Bool
    var iconPath: String?

    init(id: String = UUID().uuidString, title: String, command: String, enabled: Bool, iconPath: String? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.enabled = enabled
        self.iconPath = iconPath
    }
}

private extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }
}

final class ConfigStore: ObservableObject {
    @Published var actions: [MenuAction] = []
    @Published var allowedFolders: [String] = []
    @Published var statusBarIconPath: String?

    private let fileURL = SharedPaths.configurationFileURL

    func bootstrapIfNeeded() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            addMissingExamples()
        } else {
            load()
        }
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let configuration: Configuration
            let shouldRewrite: Bool
            if let decoded = try? JSONDecoder().decode(Configuration.self, from: data) {
                configuration = decoded
                shouldRewrite = false
            } else {
                let legacyActions = try JSONDecoder().decode([MenuAction].self, from: data)
                configuration = Configuration(actions: legacyActions)
                shouldRewrite = true
            }
            actions = configuration.actions
            allowedFolders = configuration.allowedFolders
            statusBarIconPath = configuration.statusBarIconPath
            if shouldRewrite {
                save()
            } else {
                try? mirror(data)
            }
        } catch {
            actions = []
            allowedFolders = []
            statusBarIconPath = nil
            DebugLog.append("config load failed: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let configuration = Configuration(actions: actions, allowedFolders: allowedFolders, statusBarIconPath: statusBarIconPath)
            let data = try JSONEncoder.pretty.encode(configuration)
            try data.write(to: fileURL, options: .atomic)
            try mirror(data)
            DebugLog.append("config saved count=\(actions.count)")
        } catch {
            DebugLog.append("config save failed: \(error.localizedDescription)")
        }
    }

    func addMissingExamples() {
        for example in Self.exampleActions where !actions.contains(where: { existing in
            existing.id == example.id || (existing.title == example.title && existing.command == example.command)
        }) {
            actions.append(example)
        }
        save()
    }

    func addAllowedFolders(_ urls: [URL]) {
        let paths = urls.map(\.path)
        for path in paths where !allowedFolders.contains(path) {
            allowedFolders.append(path)
        }
        save()
    }

    func hasAccess(to path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return allowedFolders.contains { folder in
            let standardizedFolder = URL(fileURLWithPath: folder).standardizedFileURL.path
            return standardizedPath == standardizedFolder || standardizedPath.hasPrefix(standardizedFolder + "/")
        }
    }

    func grantAccessIfNeeded(for path: String) -> Bool {
        load()
        if hasAccess(to: path) {
            return true
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Allow"
        panel.message = "Allow SuperKMenu to use this folder for Finder actions."

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            DebugLog.append("folder access cancelled path=\(path)")
            return false
        }

        addAllowedFolders([selectedURL])
        DebugLog.append("folder access granted path=\(selectedURL.path)")
        return hasAccess(to: path)
    }

    func enabledAction(id: String) -> MenuAction? {
        load()
        return actions.first { $0.id == id && $0.enabled }
    }

    private func mirror(_ data: Data) throws {
        let mirrorURL = SharedPaths.mirroredConfigurationFileURL
        try FileManager.default.createDirectory(at: mirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: mirrorURL, options: .atomic)
    }

    static let exampleActions = [
        MenuAction(
            id: "example-vscode",
            title: "Open in VS Code",
            command: "open -a \"Visual Studio Code\" {path}",
            enabled: false
        ),
        MenuAction(
            id: "example-terminal",
            title: "Open in Terminal",
            command: "open -a Terminal {path}",
            enabled: false
        )
    ]
}

struct Configuration: Codable {
    var actions: [MenuAction]
    var allowedFolders: [String]
    var statusBarIconPath: String?

    init(actions: [MenuAction] = [], allowedFolders: [String] = [], statusBarIconPath: String? = nil) {
        self.actions = actions
        self.allowedFolders = allowedFolders
        self.statusBarIconPath = statusBarIconPath
    }
}

enum StatusBarIcon {
    static func image(configStore: ConfigStore) -> NSImage? {
        configStore.load()
        if let path = configStore.statusBarIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let image = image(at: path) {
            image.isTemplate = true
            return image
        }

        if let image = NSImage(named: "SuperKMenu") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        let image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "SuperKMenu")
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func image(at path: String) -> NSImage? {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let image = NSImage(contentsOfFile: expandedPath) ?? fileIcon(at: expandedPath) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func fileIcon(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

final class ActionRouter {
    private let configStore: ConfigStore

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func handle(_ url: URL) {
        DebugLog.append("received url=\(url.absoluteString)")
        guard url.scheme == "superkmenu", url.host == "run" else {
            DebugLog.append("unknown action URL")
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              let action = configStore.enabledAction(id: id) else {
            DebugLog.append("missing or disabled action url=\(url.absoluteString)")
            return
        }

        run(action: action, path: path)
    }

    private func run(action: MenuAction, path: String) {
        let command = action.command.replacingOccurrences(of: "{path}", with: shellQuote(path))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { process in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DebugLog.append("action finished title=\(action.title) exit=\(process.terminationStatus) output=\(text)")
        }

        do {
            try process.run()
            DebugLog.append("running action title=\(action.title) command=\(command)")
        } catch {
            DebugLog.append("action failed title=\(action.title) error=\(error.localizedDescription)")
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SharedPaths {
    static var publicConfigurationFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".super-k-menu", isDirectory: true)
            .appendingPathComponent("actions.json")
    }

    static var mirroredConfigurationFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.chenwencheng.SuperKMenu.FinderExtension/Data/Library/Application Support/SuperKMenu", isDirectory: true)
            .appendingPathComponent("actions.json")
    }

    static var configurationFileURL: URL {
        publicConfigurationFileURL
    }
}

enum SystemActions {
    private static let extensionIdentifier = "com.chenwencheng.SuperKMenu.FinderExtension"

    static func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }

    static func enableFinderExtension() {
        if let extensionURL = finderExtensionURL() {
            run("/usr/bin/pluginkit", arguments: ["-a", extensionURL.path], logLabel: "register finder extension")
        }
        run("/usr/bin/pluginkit", arguments: ["-e", "use", "-i", extensionIdentifier], logLabel: "enable finder extension")
    }

    static func disableFinderExtension() {
        run("/usr/bin/pluginkit", arguments: ["-e", "ignore", "-i", extensionIdentifier], logLabel: "disable finder extension")
        if let extensionURL = finderExtensionURL() {
            run("/usr/bin/pluginkit", arguments: ["-r", extensionURL.path], logLabel: "unregister finder extension")
        }
    }

    static func restartFinder() {
        run("/usr/bin/killall", arguments: ["Finder"], logLabel: "restart finder")
    }

    static func plugInKitStatus() -> String {
        runAndCapture("/usr/bin/pluginkit", arguments: ["-m", "-A", "-D", "-vvv", "-i", extensionIdentifier])
    }

    private static func finderExtensionURL() -> URL? {
        Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("SuperKMenuFinderExtension.appex", isDirectory: true)
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String], logLabel: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            DebugLog.append("\(logLabel) exit=\(process.terminationStatus)")
            return process.terminationStatus == 0
        } catch {
            DebugLog.append("\(logLabel) failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func runAndCapture(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return "exit=\(process.terminationStatus)\n\(text)"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }
}

enum DebugLog {
    static let mainLogURL = URL(fileURLWithPath: "/tmp/superkmenu-main.log")

    static func append(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = mainLogURL
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

enum Diagnostics {
    static let repositoryURL = URL(string: "https://github.com/mowtwo/super-k-menu")!

    static var finderLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.chenwencheng.SuperKMenu.FinderExtension/Data/Library/Application Support/SuperKMenu", isDirectory: true)
            .appendingPathComponent("finder-extension.log")
    }

    static func snapshot(maxLogCharacters: Int = 12000) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let configText = readTail(SharedPaths.configurationFileURL, maxCharacters: maxLogCharacters / 3)
        let mirrorText = readTail(SharedPaths.mirroredConfigurationFileURL, maxCharacters: maxLogCharacters / 3)
        let mainText = readTail(DebugLog.mainLogURL, maxCharacters: maxLogCharacters)
        let finderText = readTail(finderLogURL, maxCharacters: maxLogCharacters)

        return """
        SuperKMenu Diagnostics
        Version: \(version) (\(build))
        App path: \(bundle.bundleURL.path)
        Config path: \(SharedPaths.configurationFileURL.path)
        Mirror config path: \(SharedPaths.mirroredConfigurationFileURL.path)
        Main log path: \(DebugLog.mainLogURL.path)
        Finder log path: \(finderLogURL.path)

        pluginkit:
        \(SystemActions.plugInKitStatus())

        ~/.super-k-menu/actions.json:
        \(configText)

        Finder extension mirrored actions.json:
        \(mirrorText)

        Main app log:
        \(mainText)

        Finder extension log:
        \(finderText)
        """
    }

    private static func readTail(_ url: URL, maxCharacters: Int) -> String {
        guard let data = try? Data(contentsOf: url),
              var text = String(data: data, encoding: .utf8) else {
            return "(missing)"
        }
        if text.count > maxCharacters {
            let index = text.index(text.endIndex, offsetBy: -maxCharacters)
            text = "... truncated ...\n" + String(text[index...])
        }
        return text
    }
}

enum GitHubIssueReporter {
    static func openIssue() {
        var components = URLComponents(url: Diagnostics.repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: "SuperKMenu action did not run"),
            URLQueryItem(name: "body", value: issueBody())
        ]
        guard let url = components?.url else {
            DebugLog.append("failed to build github issue url")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func issueBody() -> String {
        """
        ## What happened

        Finder menu action did not run as expected.

        ## Diagnostics

        ```text
        \(Diagnostics.snapshot(maxLogCharacters: 6000))
        ```
        """
    }
}

enum LogWindowPresenter {
    private static var controller: NSWindowController?

    static func show() {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperKMenu Logs"
        window.center()
        window.contentView = NSHostingView(rootView: LogView())
        window.isReleasedWhenClosed = false
        let windowController = NSWindowController(window: window)
        controller = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct LogView: View {
    @State private var text = Diagnostics.snapshot()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SuperKMenu Logs")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    text = Diagnostics.snapshot()
                }
                Button("Open Main Log") {
                    NSWorkspace.shared.open(DebugLog.mainLogURL)
                }
                Button("Open Finder Log") {
                    NSWorkspace.shared.open(Diagnostics.finderLogURL)
                }
                Button("Report Issue") {
                    GitHubIssueReporter.openIssue()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(18)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
