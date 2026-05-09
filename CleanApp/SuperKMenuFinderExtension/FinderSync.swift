import Cocoa
import FinderSync
import os

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "com.chenwencheng.SuperKMenu.FinderExtension", category: "FinderSync")

    override init() {
        super.init()
        refreshDirectoryURLs()
        logger.info("SuperKMenu FinderSync launched")
        appendDebugLog("FinderSync launched")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        logger.info("menu requested: \(String(describing: menuKind), privacy: .public)")
        appendDebugLog("menu requested=\(String(describing: menuKind))")

        let menu = NSMenu(title: "SuperKMenu")
        let configuration = ConfigReader.load()
        applyDirectoryURLs(configuration.allowedFolders)
        let actions = configuration.actions.filter { $0.enabled && !$0.title.isEmpty && !$0.command.isEmpty }

        if actions.isEmpty {
            let item = NSMenuItem(title: "SuperKMenu: No enabled actions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = MenuIcon.symbol("exclamationmark.circle")
            menu.addItem(item)
            menu.addItem(settingsMenuItem())
            return menu
        }

        for (index, action) in actions.enumerated() {
            let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier(action.id)
            item.representedObject = action.id
            item.tag = index + 1
            item.image = MenuIcon.image(for: action)
            menu.addItem(item)
        }

        menu.addItem(settingsMenuItem())

        return menu
    }

    private func settingsMenuItem() -> NSMenuItem {
        let settings = NSMenuItem(title: "Open SuperKMenu Settings", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        settings.image = MenuIcon.symbol("gearshape")
        return settings
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let url = URL(string: "superkmenu://settings") else {
            return
        }
        NSWorkspace.shared.open(url)
        appendDebugLog("dispatched settings url")
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let id = actionID(for: sender) else {
            appendDebugLog("missing menu item action id title=\(sender.title)")
            return
        }

        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targeted = FIFinderSyncController.default().targetedURL()
        let url = selected.first ?? targeted ?? FileManager.default.homeDirectoryForCurrentUser
        let directoryURL = directoryURL(for: url)

        appendDebugLog("action id=\(id) selected=\(selected.map(\.path).joined(separator: ", ")) target=\(targeted?.path ?? "") directory=\(directoryURL.path)")

        var components = URLComponents()
        components.scheme = "superkmenu"
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "path", value: directoryURL.path)
        ]

        guard let actionURL = components.url else {
            appendDebugLog("failed to build action URL")
            return
        }

        NSWorkspace.shared.open(actionURL)
        appendDebugLog("dispatched action url=\(actionURL.absoluteString)")
    }

    private func actionID(for item: NSMenuItem) -> String? {
        let configuration = ConfigReader.load()
        let actions = configuration.actions.filter { $0.enabled && !$0.title.isEmpty && !$0.command.isEmpty }

        if let id = item.representedObject as? String,
           actions.contains(where: { $0.id == id }) {
            return id
        }

        if let id = item.identifier?.rawValue,
           actions.contains(where: { $0.id == id }) {
            return id
        }

        if item.tag > 0, item.tag <= actions.count {
            return actions[item.tag - 1].id
        }

        return actions.first { $0.title == item.title }?.id
    }

    private func directoryURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func appendDebugLog(_ message: String) {
        DebugLog.append(message)
    }

    private func refreshDirectoryURLs() {
        applyDirectoryURLs(ConfigReader.load().allowedFolders)
    }

    private func applyDirectoryURLs(_ allowedFolders: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls = Set([
            URL(fileURLWithPath: "/", isDirectory: true),
            home,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true)
        ])

        for path in allowedFolders where !path.isEmpty {
            urls.insert(URL(fileURLWithPath: path, isDirectory: true))
        }

        FIFinderSyncController.default().directoryURLs = urls
        appendDebugLog("directory urls count=\(urls.count)")
    }
}

struct MenuAction: Codable {
    var id: String
    var title: String
    var command: String
    var enabled: Bool
    var iconPath: String?
}

enum MenuIcon {
    static func image(for action: MenuAction) -> NSImage? {
        if let iconPath = action.iconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !iconPath.isEmpty {
            if iconPath.hasPrefix("sf:") {
                return symbol(String(iconPath.dropFirst(3)))
            }
            if let image = icon(forFile: iconPath) {
                return image
            }
        }

        for appName in appNames(from: action) {
            if let image = applicationIcon(named: appName) {
                return image
            }
        }

        for appPath in appPaths(from: action.command) {
            if let image = icon(forFile: appPath) {
                return image
            }
        }

        return symbolName(for: action).flatMap(symbol) ?? symbol("command")
    }

    static func symbol(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func applicationIcon(named name: String) -> NSImage? {
        let candidates = [
            name,
            name.replacingOccurrences(of: ".app", with: ""),
            knownApplicationName(for: name)
        ].compactMap { $0 }

        for candidate in candidates {
            if let path = NSWorkspace.shared.fullPath(forApplication: candidate),
               let image = icon(forFile: path) {
                return image
            }

            let fixedPaths = [
                "/Applications/\(candidate).app",
                "/System/Applications/\(candidate).app",
                "/System/Applications/Utilities/\(candidate).app",
                "/System/Volumes/Data/Applications/\(candidate).app"
            ]
            for path in fixedPaths {
                if let image = icon(forFile: path) {
                    return image
                }
            }
        }

        return nil
    }

    private static func icon(forFile path: String) -> NSImage? {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: expandedPath)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func appNames(from action: MenuAction) -> [String] {
        var names = quotedMatches(in: action.command, pattern: #"open\s+-a\s+"([^"]+)""#)
        names.append(contentsOf: quotedMatches(in: action.command, pattern: #"open\s+-a\s+'([^']+)'"#))
        names.append(contentsOf: unquotedMatches(in: action.command, pattern: #"open\s+-a\s+([^\s{;|&]+)"#))

        if let titleApp = appNameFromTitle(action.title) {
            names.append(titleApp)
        }

        return unique(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private static func appPaths(from command: String) -> [String] {
        var paths = quotedMatches(in: command, pattern: #""([^"]+\.app)""#)
        paths.append(contentsOf: quotedMatches(in: command, pattern: #"'([^']+\.app)'"#))
        paths.append(contentsOf: unquotedMatches(in: command, pattern: #"([/\~][^\s;|&]+\.app)"#))
        return unique(paths)
    }

    private static func appNameFromTitle(_ title: String) -> String? {
        let prefixes = ["Open in ", "Open with "]
        for prefix in prefixes where title.localizedCaseInsensitiveContains(prefix) {
            let nsTitle = title as NSString
            let range = nsTitle.range(of: prefix, options: [.caseInsensitive])
            if range.location != NSNotFound {
                return nsTitle.substring(from: range.location + range.length)
            }
        }
        return nil
    }

    private static func knownApplicationName(for name: String) -> String? {
        switch name.lowercased() {
        case "vscode", "vs code", "code":
            return "Visual Studio Code"
        case "terminal":
            return "Terminal"
        case "wezterm":
            return "WezTerm"
        default:
            return nil
        }
    }

    private static func quotedMatches(in text: String, pattern: String) -> [String] {
        matches(in: text, pattern: pattern)
    }

    private static func unquotedMatches(in text: String, pattern: String) -> [String] {
        matches(in: text, pattern: pattern)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else {
                return nil
            }
            return nsText.substring(with: match.range(at: 1))
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func symbolName(for action: MenuAction) -> String? {
        let haystack = "\(action.title) \(action.command)".lowercased()
        if haystack.contains("terminal") || haystack.contains("iterm") {
            return "terminal"
        }
        if haystack.contains("visual studio code") || haystack.contains("vscode") || haystack.contains("cursor") || haystack.contains("xcode") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if haystack.contains("open") {
            return "arrow.up.forward.app"
        }
        return "command"
    }
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

enum ConfigReader {
    static func load() -> Configuration {
        for url in SharedPaths.configurationFileURLs {
            do {
                let data = try Data(contentsOf: url)
                if let configuration = try? JSONDecoder().decode(Configuration.self, from: data) {
                    DebugLog.append("config loaded path=\(url.path) count=\(configuration.actions.count)")
                    return configuration
                }
                let legacyActions = try JSONDecoder().decode([MenuAction].self, from: data)
                DebugLog.append("legacy config loaded path=\(url.path) count=\(legacyActions.count)")
                return Configuration(actions: legacyActions)
            } catch {
                DebugLog.append("config load failed path=\(url.path) error=\(error.localizedDescription)")
            }
        }
        return Configuration()
    }
}

enum SharedPaths {
    static var configurationFileURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".super-k-menu", isDirectory: true).appendingPathComponent("actions.json"),
            home.appendingPathComponent("Library/Application Support/SuperKMenu", isDirectory: true).appendingPathComponent("actions.json")
        ]
    }
}

enum DebugLog {
    static func append(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SuperKMenu", isDirectory: true)
        let url = directoryURL.appendingPathComponent("finder-extension.log")
        guard let data = line.data(using: .utf8) else {
            return
        }

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

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
