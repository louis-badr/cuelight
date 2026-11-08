// Cuelight menu bar app.
// One colored circle per open VS Code window, showing Claude Code or Codex's state there.
// The same binary is also the agent hook (`Cuelight hook <agent>`), and installs itself on launch
// (hooks in ~/.claude/settings.json and ~/.codex/hooks.json, VS Code extension). Build: ./build.sh
import AppKit
import CryptoKit

// Must stay identical to PALETTES in vscode-extension/extension.js (see docs/color.md).
let palettes: [(id: String, label: String, colors: [String])] = [
    ("vivid", "Vivid", ["#F72585", "#7209B7", "#3A0CA3", "#4361EE", "#4CC9F0"]),
    ("pastel", "Pastel", ["#CDB4DB", "#FFC8DD", "#FFAFCC", "#BDE0FE", "#A2D2FF"]),
]
let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory())
let stateDir = home.appendingPathComponent(".cuelight")

// ISO 8601 with milliseconds, like JavaScript's toISOString() in the extension.
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// MARK: - Hook mode: called by Claude Code or Codex with the event JSON on stdin

/// Writes ~/.cuelight/sessions/<agent>-<session_id>.json. Never prints, always exits 0.
func runHook(agent: String) -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let session = event["session_id"] as? String, !session.isEmpty, !session.contains("/") else { exit(0) }
    let dir = stateDir.appendingPathComponent("sessions")
    let file = dir.appendingPathComponent("\(agent)-\(session).json")

    let state: String
    switch event["hook_event_name"] as? String {
    case "SessionStart": state = "idle"
    case "Stop", "StopFailure", "Interrupt": state = "done"
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

    let record: [String: Any] = ["agent": agent, "state": state, "updatedAt": isoFormatter.string(from: Date()), "pid": agent == "claude" ? ProcessInfo.processInfo.environment["CLAUDE_PID"] ?? "" : "",
                                 // Only what the app reads: PostToolUse events can carry large tool outputs.
                                 "event": event.filter { ["session_id", "cwd", "hook_event_name"].contains($0.key) }]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: record) { try? data.write(to: file, options: .atomic) }
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "hook" {
    let agent = CommandLine.arguments.dropFirst(2).first == "codex" ? "codex" : "claude"
    runHook(agent: agent)
}

// MARK: - Setup: run at every launch, does nothing when everything is already in place

let bundleID = "com.louisbadr.cuelight"
let hookLink = stateDir.appendingPathComponent("bin/cuelight")
let hookMarker = ".cuelight/bin/cuelight hook"   // identifies our entries in both agents' config files
let claudeHookEvents = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                        "PermissionRequest", "Notification", "SubagentStart", "Stop", "StopFailure"]
let codexHookEvents = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                       "PermissionRequest", "SubagentStart", "Stop", "Interrupt"]
let eventsWithMatcher: Set = ["PreToolUse", "PostToolUse", "PermissionRequest"]

func log(_ message: String) { FileHandle.standardError.write(Data("Cuelight: \(message)\n".utf8)) }

func setUp() {
    linkHookBinary()
    updateClaudeHooks(install: true)
    updateCodexHooks(install: true)
    installVSCodeExtension()
}

/// `Cuelight uninstall` (called by install.sh --uninstall): removes our hooks and the VS Code extension.
func uninstall() -> Never {
    updateClaudeHooks(install: false)
    updateCodexHooks(install: false)
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
    let hooksValue = settings["hooks"]
    guard hooksValue == nil || hooksValue is [String: Any] else {
        log("unexpected hooks value, Claude hooks not installed"); return
    }
    var hooks = hooksValue as? [String: Any] ?? [:]
    let command = "~/\(hookMarker) claude 2>/dev/null || true"   // never fails, even if the app was deleted
    for event in claudeHookEvents {
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

/// Merges our hooks into ~/.codex/hooks.json (or removes them), after a backup. Other hooks are left untouched.
func updateCodexHooks(install: Bool) {
    let url = home.appendingPathComponent(".codex/hooks.json")
    var root: [String: Any] = [:]
    if let data = try? Data(contentsOf: url) {
        guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            log("~/.codex/hooks.json is not plain JSON, hooks not installed"); return
        }
        root = parsed
    }
    let hooksValue = root["hooks"]
    guard hooksValue == nil || hooksValue is [String: Any] else {
        log("unexpected hooks value, Codex hooks not installed"); return
    }
    var hooks = hooksValue as? [String: Any] ?? [:]
    let command = "~/\(hookMarker) codex 2>/dev/null || true"
    for event in codexHookEvents {
        guard let groups = (hooks[event] ?? []) as? [[String: Any]] else { log("unexpected Codex hooks.\(event), hooks not installed"); return }
        let others = groups.filter { group in
            !((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(hookMarker) == true }
        }
        var ours: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        if eventsWithMatcher.contains(event) { ours["matcher"] = "*" }
        hooks[event] = install ? others + [ours] : (others.isEmpty ? nil : others)
    }
    if NSDictionary(dictionary: hooks).isEqual(to: root["hooks"] as? [String: Any] ?? [:]) { return }
    root["hooks"] = hooks.isEmpty ? nil : hooks

    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("hooks.json.cuelight-backup-\(stamp)")
        do { try fm.copyItem(at: url, to: backup) } catch { log("Codex hooks backup: \(error)"); return }
    }
    do {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    } catch { log("Codex hooks write: \(error)") }
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

enum AgentState: Int { case none = 0, idle, working, done, waiting   // higher = more urgent
    var label: String {
        switch self {
        case .none: return "No agent running"
        case .idle: return "Agent idle"
        case .working: return "Agent working"
        case .done: return "Agent done"
        case .waiting: return "Agent needs you"
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

/// Most urgent agent state per window id. A session belongs to the window whose path is its cwd's longest prefix.
func statesByWindow(_ windows: [ProjectWindow]) -> [String: AgentState] {
    var states: [String: AgentState] = [:]
    for url in jsonFiles("sessions") {
        guard let json = readJSON(url),
              let event = json["event"] as? [String: Any],
              let cwd = event["cwd"] as? String else { continue }
        if let pid = pidValue(json["pid"]), !isAlive(pid) { try? FileManager.default.removeItem(at: url); continue }
        // Codex does not expose its host PID to hooks. SessionEnd normally removes the file; this
        // fallback prevents a crashed client from leaving a light behind forever.
        if pidValue(json["pid"]) == nil,
           let updatedAt = (json["updatedAt"] as? String).flatMap(isoFormatter.date(from:)),
           Date().timeIntervalSince(updatedAt) > 24 * 60 * 60 {
            try? FileManager.default.removeItem(at: url); continue
        }
        let owner = windows
            .filter { cwd == $0.path || cwd.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        var state: AgentState
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

/// Palette chosen in the menu (~/.cuelight/settings.json), vivid by default.
func currentPalette() -> String {
    let id = readJSON(settingsFile)?["palette"] as? String
    return palettes.contains { $0.id == id } ? id! : "vivid"
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

let circleDiameter: CGFloat = 12

func circleImage(color: NSColor, state: AgentState) -> NSImage {
    let height: CGFloat = 16, d = circleDiameter
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
            // Tinted disc; the turning arc is a separate layer (spinnerLayer).
            color.withAlphaComponent(0.3).setFill(); NSBezierPath(ovalIn: rect).fill()
        case .waiting:
            color.setFill(); NSBezierPath(ovalIn: rect).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
        }
        return true
    }
    image.isTemplate = false
    return image
}

/// Arc turning around the edge of a working circle. Core Animation spins it in the render server,
/// so the app doesn't wake up for each frame.
func spinnerLayer(color: NSColor, in bounds: NSRect, scale: CGFloat) -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.frame = bounds
    layer.contentsScale = scale
    let center = CGPoint(x: bounds.midX - bounds.minX, y: bounds.midY - bounds.minY)
    let path = CGMutablePath()
    path.addArc(center: center, radius: circleDiameter / 2 - 1.25,
                startAngle: 0, endAngle: -110 * .pi / 180, clockwise: true)
    layer.path = path
    layer.fillColor = nil
    layer.strokeColor = color.cgColor
    layer.lineWidth = 2.5
    layer.lineCap = .round
    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
    spin.fromValue = 0
    spin.toValue = -2 * CGFloat.pi   // clockwise, one turn per second
    spin.duration = 1
    spin.repeatCount = .infinity
    spin.isRemovedOnCompletion = false
    layer.add(spin, forKey: "spin")
    return layer
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
    var states: [String: AgentState] = [:]
    var colors: [String: NSColor] = [:]        // by window name; cleared when colors.json or settings.json change
    var images: [String: NSImage] = [:]        // cache: "<color>-<state>"
    var shown: [String: String] = [:]          // image key currently on each item
    var spinners: [String: (layer: CAShapeLayer, key: String)] = [:]
    var watchers: [DispatchSourceFileSystemObject] = []
    var refreshPending = false
    var groupCheck: DispatchWorkItem?
    var regrouped = false                      // lights re-created, not seen side by side since

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().async { setUp() }

        // Ask once for Accessibility (needed only to maximize the window).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Re-read the state folder when it changes, instead of polling it.
        for sub in ["windows", "sessions"] {
            try? FileManager.default.createDirectory(at: stateDir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        watch(stateDir) { [weak self] in self?.colors = [:] }   // colors.json, settings.json (atomic writes = renames)
        watch(stateDir.appendingPathComponent("windows"))
        watch(stateDir.appendingPathComponent("sessions"))

        refresh()
        // Slow fallback: notices dead processes (VS Code or an agent that crashed) and missed events.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }

        // The lights move whenever an icon is added or removed in the menu bar: check they are still side by side.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleGroupCheck()
        }
    }

    /// Checks the lights once they stop moving (macOS places a new item in several steps).
    func scheduleGroupCheck() {
        groupCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkGrouping() }
        groupCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// macOS puts a new menu bar icon at the left end of the icons, so an icon added between two lights
    /// created at different times (another app's, or ours for a window opened later) splits them.
    /// Re-creating all the lights at once puts them back side by side, at the left end.
    func checkGrouping() {
        let frames = items.values.compactMap { $0.button?.window?.frame }.sorted { $0.minX < $1.minX }
        // x = 0: not placed yet. Different y: moving to another screen. The next move schedules another check.
        guard frames.count > 1, frames.allSatisfy({ $0.minX != 0 && $0.minY == frames[0].minY }) else { return }
        let split = zip(frames, frames.dropFirst()).contains { $1.minX - $0.maxX > 2 }
        if !split { regrouped = false; return }
        if regrouped { return }   // already tried: don't loop if macOS keeps them apart (crowded menu bar)
        regrouped = true
        for item in items.values { NSStatusBar.system.removeStatusItem(item) }
        items = [:]
        shown = [:]
        spinners = [:]
        refresh()
    }

    /// Calls `refresh` when entries in `dir` are added, removed or renamed. Bursts of changes become one refresh.
    func watch(_ dir: URL, before: (() -> Void)? = nil) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            before?()
            if self.refreshPending { return }
            self.refreshPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.refreshPending = false
                self.refresh()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers.append(source)
    }

    func refresh() {
        let open = openWindows()
        states = statesByWindow(open)
        for w in open where colors[w.name] == nil { colors[w.name] = colorFor(w.name) }
        let ids = Set(open.map(\.id))
        for (id, item) in items where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
            shown[id] = nil
            spinners[id] = nil
        }
        windows = [:]
        for w in open {
            windows[w.id] = w
            if items[w.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: itemWidth)
                // A new name every time: macOS puts an item back where an item of the same name was
                // (after a Cmd-drag, for instance), which can be away from the other lights. An item
                // with a new name lands at the left end of the icons.
                item.autosaveName = "light-\(UUID().uuidString)"
                item.button?.identifier = NSUserInterfaceItemIdentifier(w.id)
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.wantsLayer = true
                items[w.id] = item
            }
        }
        redraw()
    }

    /// Touches a status item only when its image, spinner or tooltip actually changes.
    func redraw() {
        for (id, item) in items {
            guard let w = windows[id], let button = item.button else { continue }
            let state = states[id] ?? AgentState.none
            let color = colors[w.name] ?? colorFor(w.name)
            let key = "\(color.description)-\(state.rawValue)"
            if shown[id] != key {
                if images[key] == nil { images[key] = circleImage(color: color, state: state) }
                button.image = images[key]
                shown[id] = key
            }

            let spinnerKey = state == .working ? "\(color.description)-\(button.bounds)" : nil
            if spinners[id]?.key != spinnerKey {
                spinners[id]?.layer.removeFromSuperlayer()
                spinners[id] = nil
                if let spinnerKey, let host = button.layer {
                    let layer = spinnerLayer(color: color, in: button.bounds, scale: button.window?.backingScaleFactor ?? 2)
                    host.addSublayer(layer)
                    spinners[id] = (layer, spinnerKey)
                }
            }

            let tip = "\(w.name) · \(state.label)"
            if button.toolTip != tip { button.toolTip = tip }
        }
    }

    @objc func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let w = windows[id] else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "\(w.name)  ·  \((states[id] ?? AgentState.none).label)", action: nil, keyEquivalent: "")
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
        colors = [:]
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
