// Cuelight menu bar app.
// One colored circle per open VS Code window, showing Claude Code's state there.
// The same binary is also the Claude Code hook (`Cuelight hook`), and installs itself on launch
// (hooks in ~/.claude/settings.json, VS Code extension). Build: ./build.sh
import AppKit
import CryptoKit

// Must stay identical to PALETTES in vscode-extension/extension.js (see docs/color.md).
let palettes: [(id: String, label: String, colors: [String])] = [
    ("pastel", "Pastel", ["#9DBDF2", "#97D8B2", "#F2A6A0", "#C6B0F2", "#93D3DD", "#F0ABCD", "#F6C28E", "#D2DE92"]),
    ("soft", "Soft", ["#4E6FAE", "#4E8B6B", "#B5524F", "#7D62AE", "#3F8C99", "#A85A85", "#C07A3E", "#7F8C3F"]),
    ("vivid", "Vivid", ["#2D5BE3", "#13915F", "#D03A3A", "#7B3FE4", "#0E8AA0", "#C93782", "#DD6B20", "#5E9E1E"]),
]
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let stateDir = home.appendingPathComponent(".cuelight")

// ISO 8601 with milliseconds, like JavaScript's toISOString() in the extension.
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// MARK: - Hook mode: called by Claude Code with the event JSON on stdin

/// Writes ~/.cuelight/sessions/<session_id>.json. Never prints, always exits 0.
func runHook() -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let session = event["session_id"] as? String, !session.isEmpty, !session.contains("/") else { exit(0) }
    let dir = stateDir.appendingPathComponent("sessions")
    let file = dir.appendingPathComponent("\(session).json")

    let state: String
    switch event["hook_event_name"] as? String {
    case "SessionStart": state = "idle"
    case "Stop", "StopFailure": state = "done"
    case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart": state = "working"
    case "PermissionRequest": state = "waiting"
    case "Notification":
        // idle_prompt = Claude finished a while ago and still waits for a prompt: keep the current state,
        // rewriting "done" would bring back a result already seen. Searched in the raw text
        // so we don't depend on the exact name of the type field.
        if String(decoding: input, as: UTF8.self).contains("idle_prompt") { exit(0) }
        state = "waiting"
    case "SessionEnd": try? FileManager.default.removeItem(at: file); exit(0)
    default: exit(0)
    }

    let record: [String: Any] = ["state": state, "updatedAt": isoFormatter.string(from: Date()), "pid": ProcessInfo.processInfo.environment["CLAUDE_PID"] ?? "", "event": event]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: record) { try? data.write(to: file, options: .atomic) }
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "hook" { runHook() }

// MARK: - Setup: run at every launch, does nothing when everything is already in place

let bundleID = "com.louisbadr.cuelight"
let hookLink = stateDir.appendingPathComponent("bin/cuelight")
let hookMarker = ".cuelight/bin/cuelight hook"   // identifies our entries in ~/.claude/settings.json
let hookEvents = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                  "PermissionRequest", "Notification", "SubagentStart", "Stop", "StopFailure"]
let eventsWithMatcher: Set = ["PreToolUse", "PostToolUse", "PermissionRequest"]

func log(_ message: String) { FileHandle.standardError.write(Data("Cuelight: \(message)\n".utf8)) }

func setUp() {
    linkHookBinary()
    updateClaudeHooks(install: true)
    installVSCodeExtension()
}

/// `Cuelight uninstall` (called by install.sh --uninstall): removes our hooks and the VS Code extension.
func uninstall() -> Never {
    updateClaudeHooks(install: false)
    if let cli = vscodeCLI() {
        let p = Process()
        p.executableURL = cli
        p.arguments = ["--uninstall-extension", "louisbadr.cuelight"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
    exit(0)
}

/// ~/.cuelight/bin/cuelight → this binary. The hook command goes through this link,
/// so settings.json doesn't change when the app moves.
func linkHookBinary() {
    guard let exe = Bundle.main.executablePath else { return }
    let fm = FileManager.default
    if (try? fm.destinationOfSymbolicLink(atPath: hookLink.path)) == exe { return }
    try? fm.createDirectory(at: hookLink.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.removeItem(at: hookLink)
    do { try fm.createSymbolicLink(atPath: hookLink.path, withDestinationPath: exe) } catch { log("hook link: \(error)") }
}

/// Merges our hooks into ~/.claude/settings.json (or removes them), after a backup. Other hooks are left untouched.
func updateClaudeHooks(install: Bool) {
    let url = home.appendingPathComponent(".claude/settings.json")
    var settings: [String: Any] = [:]
    if let data = try? Data(contentsOf: url) {
        guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("~/.claude/settings.json is not plain JSON, hooks not installed"); return
        }
        settings = parsed
    }
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    let command = "~/\(hookMarker) 2>/dev/null || true"   // never fails, even if the app was deleted
    for event in hookEvents {
        guard let groups = (hooks[event] ?? []) as? [[String: Any]] else { log("unexpected hooks.\(event), hooks not installed"); return }
        let others = groups.filter { group in
            !((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(hookMarker) == true }
        }
        var ours: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        if eventsWithMatcher.contains(event) { ours["matcher"] = "*" }
        hooks[event] = install ? others + [ours] : (others.isEmpty ? nil : others)
    }
    if NSDictionary(dictionary: hooks).isEqual(to: settings["hooks"] as? [String: Any] ?? [:]) { return }
    settings["hooks"] = hooks.isEmpty ? nil : hooks

    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.cuelight-backup-\(stamp)")
        do { try fm.copyItem(at: url, to: backup) } catch { log("settings backup: \(error)"); return }
    }
    do {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    } catch { log("settings write: \(error)") }
}

/// Installs the bundled .vsix with VS Code's CLI, unless this version is already installed.
func installVSCodeExtension() {
    guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
          let vsix = Bundle.main.url(forResource: "cuelight", withExtension: "vsix"),
          let cli = vscodeCLI() else { return }
    let installed = home.appendingPathComponent(".vscode/extensions/louisbadr.cuelight-\(version)")
    if FileManager.default.fileExists(atPath: installed.path) { return }
    let p = Process()
    p.executableURL = cli
    p.arguments = ["--install-extension", vsix.path, "--force"]
    p.standardOutput = FileHandle.nullDevice
    do { try p.run() } catch { log("extension install: \(error)") }
}

func vscodeCLI() -> URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")?
        .appendingPathComponent("Contents/Resources/app/bin/code")
}

if CommandLine.arguments.dropFirst().first == "uninstall" { uninstall() }

enum ClaudeState: Int { case none = 0, idle, working, done, waiting   // higher = more urgent
    var label: String {
        switch self {
        case .none: return "Claude not running"
        case .idle: return "Claude idle"
        case .working: return "Claude working"
        case .done: return "Claude done"
        case .waiting: return "Claude needs you"
        }
    }
}

struct ProjectWindow {
    let id: String; let path: String; let name: String; let openedAt: String
    let focused: Bool; let lastFocusedAt: Date?
}

// MARK: - Reading ~/.cuelight

func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func jsonFiles(_ sub: String) -> [URL] {
    let dir = stateDir.appendingPathComponent(sub)
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return urls.filter { $0.pathExtension == "json" }
}

func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

func pidValue(_ any: Any?) -> Int32? {
    if let n = any as? Int { return Int32(n) }
    if let s = any as? String, let n = Int32(s) { return n }
    return nil
}

func openWindows() -> [ProjectWindow] {
    var result: [ProjectWindow] = []
    for url in jsonFiles("windows") {
        guard let json = readJSON(url), let path = json["path"] as? String, let name = json["name"] as? String else { continue }
        if let pid = pidValue(json["pid"]), !isAlive(pid) {   // VS Code died without cleaning up
            try? FileManager.default.removeItem(at: url)
            continue
        }
        result.append(ProjectWindow(id: url.deletingPathExtension().lastPathComponent, path: path, name: name,
                                    openedAt: json["openedAt"] as? String ?? "",
                                    focused: json["focused"] as? Bool ?? false,
                                    lastFocusedAt: (json["lastFocusedAt"] as? String).flatMap(isoFormatter.date(from:))))
    }
    return result.sorted { $0.openedAt < $1.openedAt }
}

/// Most urgent Claude state per window id. A session belongs to the window whose path is its cwd's longest prefix.
func statesByWindow(_ windows: [ProjectWindow]) -> [String: ClaudeState] {
    var states: [String: ClaudeState] = [:]
    for url in jsonFiles("sessions") {
        guard let json = readJSON(url),
              let event = json["event"] as? [String: Any],
              let cwd = event["cwd"] as? String else { continue }
        if let pid = pidValue(json["pid"]), !isAlive(pid) { try? FileManager.default.removeItem(at: url); continue }
        let owner = windows
            .filter { cwd == $0.path || cwd.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        var state: ClaudeState
        switch json["state"] as? String {
        case "working": state = .working
        case "waiting": state = .waiting
        case "done": state = .done
        default: state = .idle
        }
        // A result counts as seen once its window had the focus after the turn ended.
        if state == .done, let owner {
            let doneAt = (json["updatedAt"] as? String).flatMap(isoFormatter.date(from:)) ?? .distantPast
            if owner.focused || (owner.lastFocusedAt.map { $0 >= doneAt } ?? false) { state = .idle }
        }
        if let owner, state.rawValue > (states[owner.id]?.rawValue ?? 0) { states[owner.id] = state }
    }
    return states
}

// MARK: - Colors

func colorFromHex(_ hex: String) -> NSColor {
    let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let v = UInt32(s.prefix(6), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let settingsFile = stateDir.appendingPathComponent("settings.json")

/// Palette chosen in the menu (~/.cuelight/settings.json), pastel by default.
func currentPalette() -> String {
    let id = readJSON(settingsFile)?["palette"] as? String
    return palettes.contains { $0.id == id } ? id! : "pastel"
}

func setPalette(_ id: String) {
    var settings = readJSON(settingsFile) ?? [:]
    settings["palette"] = id
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: settings) { try? data.write(to: settingsFile, options: .atomic) }
}

func colorFor(_ name: String) -> NSColor {
    if let overrides = readJSON(stateDir.appendingPathComponent("colors.json")), let hex = overrides[name] as? String {
        return colorFromHex(hex)
    }
    let colors = palettes.first { $0.id == currentPalette() }!.colors
    let hash = Array(SHA256.hash(data: Data(name.utf8)))
    let n = UInt32(hash[0]) << 24 | UInt32(hash[1]) << 16 | UInt32(hash[2]) << 8 | UInt32(hash[3])
    return colorFromHex(colors[Int(n % UInt32(colors.count))])
}

// MARK: - Drawing

// One status item per window, so each one is its own button. Narrower than squareLength:
// macOS adds its own spacing between items.
let itemWidth: CGFloat = 12

func circleImage(color: NSColor, state: ClaudeState, angle: CGFloat) -> NSImage {
    let height: CGFloat = 16, d: CGFloat = 12
    let image = NSImage(size: NSSize(width: itemWidth, height: height), flipped: false) { _ in
        let rect = NSRect(x: (itemWidth - d) / 2, y: (height - d) / 2, width: d, height: d)
        switch state {
        case .none:
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            color.setStroke(); ring.stroke()
        case .idle:
            color.withAlphaComponent(0.3).setFill(); NSBezierPath(ovalIn: rect).fill()
        case .done:
            color.setFill(); NSBezierPath(ovalIn: rect).fill()
        case .working:
            // Spinner: tinted disc, with an arc turning around its edge.
            color.withAlphaComponent(0.3).setFill(); NSBezierPath(ovalIn: rect).fill()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: d / 2 - 1.25,
                          startAngle: angle, endAngle: angle - 110, clockwise: true)
            arc.lineWidth = 2.5
            arc.lineCapStyle = .round
            color.setStroke(); arc.stroke()
        case .waiting:
            color.setFill(); NSBezierPath(ovalIn: rect).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
        }
        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Focus + maximize the VS Code window

func focusAndMaximize(_ window: ProjectWindow) {
    // VS Code reuses the window already open on this folder and brings it to the front.
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "Visual Studio Code", window.path]
    try? open.run()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { maximizeFocusedVSCodeWindow() }
}

func maximizeFocusedVSCodeWindow() {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.VSCode").first else { return }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
    let axWindow = value as! AXUIElement

    // Pick the screen holding the window's top-left corner (AX coordinates: origin top-left of the main screen).
    var posRef: CFTypeRef?
    var origin = CGPoint.zero
    if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success, let posRef {
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
    }
    guard let mainHeight = NSScreen.screens.first?.frame.height else { return }
    let cocoaPoint = NSPoint(x: origin.x + 1, y: mainHeight - origin.y - 1)
    let screen = NSScreen.screens.first { $0.frame.contains(cocoaPoint) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }

    var newOrigin = CGPoint(x: visible.minX, y: mainHeight - visible.maxY)
    var newSize = CGSize(width: visible.width, height: visible.height)
    if let p = AXValueCreate(.cgPoint, &newOrigin) { AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, p) }
    if let s = AXValueCreate(.cgSize, &newSize) { AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, s) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var items: [String: NSStatusItem] = [:]
    var windows: [String: ProjectWindow] = [:]
    var states: [String: ClaudeState] = [:]
    var tick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().async { setUp() }

        // Ask once for Accessibility (needed only to maximize the window).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        refresh()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
    }

    /// 30 times a second: animate working circles; every second: re-read the state folder.
    func step() {
        tick += 1
        if tick % 30 == 0 { refresh() } else { redraw(onlyWorking: true) }
    }

    func refresh() {
        let open = openWindows()
        states = statesByWindow(open)
        let ids = Set(open.map(\.id))
        for (id, item) in items where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
        }
        windows = [:]
        for w in open {
            windows[w.id] = w
            if items[w.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: itemWidth)
                item.button?.identifier = NSUserInterfaceItemIdentifier(w.id)
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                items[w.id] = item
            }
        }
        redraw(onlyWorking: false)
    }

    func redraw(onlyWorking: Bool) {
        let angle = CGFloat(-(tick * 12) % 360)   // clockwise, one turn per second
        for (id, item) in items {
            guard let w = windows[id] else { continue }
            let state = states[id] ?? ClaudeState.none
            if onlyWorking && state != .working { continue }
            item.button?.image = circleImage(color: colorFor(w.name), state: state, angle: angle)
            item.button?.toolTip = "\(w.name) · \(state.label)"
        }
    }

    @objc func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let w = windows[id] else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "\(w.name)  ·  \((states[id] ?? ClaudeState.none).label)", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            let paletteMenu = NSMenu()
            for p in palettes {
                let entry = paletteMenu.addItem(withTitle: p.label, action: #selector(choosePalette(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = p.id
                entry.state = p.id == currentPalette() ? .on : .off
            }
            menu.addItem(withTitle: "Palette", action: nil, keyEquivalent: "").submenu = paletteMenu
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Cuelight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else {
            focusAndMaximize(w)
        }
    }

    @objc func choosePalette(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setPalette(id)
        redraw(onlyWorking: false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
