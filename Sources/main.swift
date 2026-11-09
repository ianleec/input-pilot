import AppKit
import Carbon
import UniformTypeIdentifiers

enum Mode: String, Codable, CaseIterable {
    case simplified, traditional
    var title: String { self == .simplified ? "简体拼音" : "繁体拼音" }
}
struct Rule: Codable, Equatable {
    let bundleID: String
    var name: String
    var mode: Mode
}
struct Configuration: Codable, Equatable {
    var enabled = true
    var simplifiedID = "com.apple.inputmethod.SCIM.ITABC"
    var traditionalID = "com.apple.inputmethod.TCIM.Pinyin"
    var rules: [Rule] = []
    func mode(for bundleID: String) -> Mode {
        rules.first(where: { $0.bundleID == bundleID })?.mode ?? .simplified
    }
    mutating func upsert(_ rule: Rule) {
        rules.removeAll { $0.bundleID == rule.bundleID }
        rules.append(rule)
        rules.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
final class Store {
    let defaults: UserDefaults
    private let key = "configuration.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() throws -> Configuration {
        guard let data = defaults.data(forKey: key) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
    func save(_ value: Configuration) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
struct Source {
    let ref: TISInputSource
    let id: String
    let name: String
}
enum InputSources {
    static func string(_ source: TISInputSource, _ key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    static func available() -> [Source] {
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true,
                      kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        return list.map { Source(ref: $0, id: string($0, kTISPropertyInputSourceID), name: string($0, kTISPropertyLocalizedName)) }
    }
    static func currentID() -> String {
        string(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
    }
    static func select(_ id: String) throws {
        if currentID() == id { return }
        guard let source = available().first(where: { $0.id == id }) else {
            throw NSError(domain: "PinyinPilot", code: 1, userInfo: [NSLocalizedDescriptionKey: "输入法未启用：\(id)。请先在系统设置 → 键盘 → 输入法中添加对应拼音输入法。"])
        }
        let result = TISSelectInputSource(source.ref)
        guard result == noErr else { throw NSError(domain: "TIS", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "系统拒绝切换输入法（\(result)）。"]) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let store = Store()
    var config = Configuration()
    var item: NSStatusItem!
    var window: NSWindow!
    let table = NSTableView()
    let simplePicker = NSPopUpButton()
    let traditionalPicker = NSPopUpButton()
    let modePicker = NSPopUpButton()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let pauseButton = NSButton(checkboxWithTitle: "启用按应用自动切换", target: nil, action: nil)
    var sources: [Source] = []
    var activationWork: DispatchWorkItem?
    var activationGeneration = 0
    var lastObservedPID: pid_t?
    var frontmostTimer: Timer?
    var monitoringActivity: NSObjectProtocol?
    var lastExternalApp: NSRunningApplication?
    var lastError = ""
    var recentOutcome = "等待应用切换"
    var testEvents: [[String: String]] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { config = try store.load() } catch {
            config.enabled = false
            lastError = "配置无法读取；已暂停，原配置未覆盖。\(error.localizedDescription)"
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "IP"
        rebuildMenu()
        buildWindow()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // A hidden/minimized settings window must not suspend the menu bar service.
        updateMonitoringActivity()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.config.enabled,
                      let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier != self.lastObservedPID else { return }
                self.schedule(app)
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        frontmostTimer = timer
        if let app = NSWorkspace.shared.frontmostApplication { schedule(app) }
        if CommandLine.arguments.contains("--minimized-regression") { runMinimizedRegression() }
        else if CommandLine.arguments.contains("--integration-test") { runIntegrationTest() }
        else { showSettings() }
    }
    func persist() {
        do { try store.save(config); lastError = "" } catch { lastError = "保存失败：\(error.localizedDescription)" }
        rebuildMenu()
        refreshStatus()
        updateMonitoringActivity()
    }
    func updateMonitoringActivity() {
        if config.enabled && monitoringActivity == nil {
            // Prevent App Nap, but explicitly permit the Mac to sleep when idle.
            monitoringActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "按前台应用及时切换本地输入法")
        } else if !config.enabled, let activity = monitoringActivity {
            ProcessInfo.processInfo.endActivity(activity); monitoringActivity = nil
            activationGeneration += 1; activationWork?.cancel()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        frontmostTimer?.invalidate()
        if let activity = monitoringActivity { ProcessInfo.processInfo.endActivity(activity) }
    }
    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Input Pilot · 本地输入法切换", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let enabled = NSMenuItem(title: config.enabled ? "暂停自动切换" : "恢复自动切换", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self; menu.addItem(enabled)
        let settings = NSMenuItem(title: "应用规则与输入法设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let about = NSMenuItem(title: "关于Input Pilot…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出Input Pilot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        item.menu = menu
        item.button?.title = config.enabled ? "IP" : "IP ⏸"
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Input Pilot", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", .credits: NSAttributedString(string: "按应用自动切换简体／繁体拼音\n规则仅存本机 · 沙盒禁止联网\n关闭设置窗口后继续在菜单栏运行")])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleEnabled() {
        config.enabled.toggle(); pauseButton.state = config.enabled ? .on : .off
        persist(); if let app = NSWorkspace.shared.frontmostApplication { schedule(app) }
    }
    @objc func checkboxChanged() {
        config.enabled = pauseButton.state == .on; persist()
        if let app = lastExternalApp { schedule(app) }
    }
    @objc func activated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        schedule(app)
    }
    @objc func woke() { if let app = NSWorkspace.shared.frontmostApplication { schedule(app) } }
    func schedule(_ app: NSRunningApplication) {
        activationWork?.cancel()
        activationGeneration += 1
        lastObservedPID = app.processIdentifier
        guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        lastExternalApp = app
        guard config.enabled else { refreshStatus(); return }
        let generation = activationGeneration
        // Some apps/system document input-source restoration finish after activation.
        // Bound retries to this activation, and never enforce indefinitely while typing.
        for delay in [0.12, 0.4, 0.8, 1.3] {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.config.enabled, self.activationGeneration == generation,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                self.apply(id: id, name: app.localizedName ?? id, generation: generation)
            }
            activationWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
    func apply(id: String, name: String, generation: Int) {
        let mode = config.mode(for: id)
        let target = mode == .simplified ? config.simplifiedID : config.traditionalID
        do {
            try InputSources.select(target)
            // TIS selection can settle asynchronously. Confirm after the selection finishes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self, self.config.enabled, self.activationGeneration == generation,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id else { return }
                let actual = InputSources.currentID()
                self.lastError = actual == target ? "" : "系统未保持所选输入法，请关闭系统的‘自动切换到文稿的输入法’后重试。"
                self.recentOutcome = "\(name) → \(mode.title)"
                self.testEvents.append(["app": id, "expected": target, "actual": actual])
                if self.testEvents.count > 20 { self.testEvents.removeFirst() }
                self.refreshStatus()
            }
        } catch { lastError = error.localizedDescription; refreshStatus() }
    }
    func refreshStatus() {
        statusLabel.stringValue = lastError.isEmpty ? "\(config.enabled ? recentOutcome : "已暂停")\n当前输入法：\(InputSources.currentID())" : lastError
        statusLabel.textColor = lastError.isEmpty ? .secondaryLabelColor : .systemRed
    }
    @objc func showSettings() {
        refreshSources(); table.reloadData(); refreshStatus()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 570), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Input Pilot · 应用输入法规则"; window.center(); window.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 22), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -22), root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)])
        let title = NSTextField(labelWithString: "按应用，自动切换简体／繁体拼音")
        title.font = .systemFont(ofSize: 21, weight: .semibold); root.addArrangedSubview(title)
        root.addArrangedSubview(NSTextField(labelWithString: "未配置应用默认简体拼音。删除规则后恢复默认。"))
        pauseButton.target = self; pauseButton.action = #selector(checkboxChanged); pauseButton.state = config.enabled ? .on : .off; root.addArrangedSubview(pauseButton)
        let inputs = NSStackView(views: [NSTextField(labelWithString: "简体："), simplePicker, NSTextField(labelWithString: "繁体："), traditionalPicker])
        inputs.spacing = 8
        simplePicker.target = self; simplePicker.action = #selector(sourcesChanged)
        traditionalPicker.target = self; traditionalPicker.action = #selector(sourcesChanged)
        simplePicker.widthAnchor.constraint(equalToConstant: 220).isActive = true
        traditionalPicker.widthAnchor.constraint(equalToConstant: 220).isActive = true
        root.addArrangedSubview(inputs)
        let refresh = NSButton(title: "刷新已启用输入法", target: self, action: #selector(refreshClicked)); root.addArrangedSubview(refresh)
        for (id, label, width) in [("name", "应用名称", 220.0), ("bundle", "应用标识", 310.0), ("mode", "输入法", 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = label; column.width = width; table.addTableColumn(column)
        }
        table.delegate = self; table.dataSource = self; table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        modePicker.addItems(withTitles: Mode.allCases.map(\.title)); modePicker.selectItem(at: 1)
        let add = NSButton(title: "添加应用…", target: self, action: #selector(addApp))
        let change = NSButton(title: "修改所选规则", target: self, action: #selector(changeRule))
        let remove = NSButton(title: "删除所选规则", target: self, action: #selector(removeRule))
        let actions = NSStackView(views: [modePicker, add, change, remove]); actions.spacing = 10; root.addArrangedSubview(actions)
        statusLabel.font = .systemFont(ofSize: 11); root.addArrangedSubview(statusLabel)
        root.addArrangedSubview(NSTextField(wrappingLabelWithString: "隐私：仅保存应用标识与规则；不读取按键、输入内容、剪贴板或窗口标题。已启用沙盒且无联网权限。关闭窗口后继续在菜单栏运行。"))
    }
    func refreshSources() {
        sources = InputSources.available()
        for (picker, selected) in [(simplePicker, config.simplifiedID), (traditionalPicker, config.traditionalID)] {
            picker.removeAllItems()
            for source in sources { picker.addItem(withTitle: source.name); picker.lastItem?.representedObject = source.id }
            if let index = sources.firstIndex(where: { $0.id == selected }) { picker.selectItem(at: index) }
            else { picker.addItem(withTitle: "未启用 · \(selected)"); picker.lastItem?.representedObject = selected; picker.selectItem(at: sources.count) }
        }
    }
    @objc func refreshClicked() { refreshSources(); refreshStatus() }
    @objc func sourcesChanged() {
        guard let simple = simplePicker.selectedItem?.representedObject as? String, let traditional = traditionalPicker.selectedItem?.representedObject as? String else { return }
        config.simplifiedID = simple; config.traditionalID = traditional; persist()
    }
    var chosenMode: Mode { modePicker.indexOfSelectedItem == 0 ? .simplified : .traditional }
    @objc func addApp() {
        let panel = NSOpenPanel(); panel.title = "选择需要设置输入法的应用"; panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                self.config.upsert(Rule(bundleID: id, name: name, mode: self.chosenMode))
            }
            self.persist(); self.table.reloadData()
        }
    }
    @objc func changeRule() {
        let row = table.selectedRow; guard config.rules.indices.contains(row) else { return }
        config.rules[row].mode = chosenMode; persist(); table.reloadData()
    }
    @objc func removeRule() {
        let row = table.selectedRow; guard config.rules.indices.contains(row) else { return }
        config.rules.remove(at: row); persist(); table.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { config.rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = config.rules[row]
        let value = tableColumn?.identifier.rawValue == "name" ? rule.name : tableColumn?.identifier.rawValue == "bundle" ? rule.bundleID : rule.mode.title
        return NSTextField(labelWithString: value)
    }
    func runMinimizedRegression() {
        let saved = config
        let source = InputSources.currentID()
        let original = NSWorkspace.shared.frontmostApplication
        guard let discord = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hnc.Discord").first,
              let wechat = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first else {
            print("Regression requires running Discord and WeChat"); NSApp.terminate(nil); return
        }
        config.enabled = true
        config.upsert(Rule(bundleID: "com.hnc.Discord", name: "Discord", mode: .traditional))
        config.rules.removeAll { $0.bundleID == "com.tencent.xinWeChat" }
        updateMonitoringActivity()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.miniaturize(nil)
        var checks: [[String: Any]] = []
        let steps: [(NSRunningApplication, Mode, Bool)] = [
            (discord, .traditional, false), (wechat, .simplified, false),
            (discord, .traditional, true), (wechat, .simplified, true),
            (discord, .traditional, false), (wechat, .simplified, false)
        ]
        func finish() {
            self.config = saved; self.activationGeneration += 1; self.config.enabled = false
            self.updateMonitoringActivity()
            original?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? InputSources.select(source)
                let report: [String: Any] = ["version": "1.0.1", "passed": checks.count == steps.count && checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks]
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PinyinPilot-minimized-regression.json")
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
                } catch { print(error) }
                NSApp.terminate(nil)
            }
        }
        func step(_ index: Int) {
            guard index < steps.count else { finish(); return }
            let (app, mode, inject) = steps[index]
            app.activate(options: [])
            if inject {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                    try? InputSources.select(mode == .traditional ? self.config.simplifiedID : self.config.traditionalID)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                let actual = InputSources.currentID()
                let expected = mode == .traditional ? self.config.traditionalID : self.config.simplifiedID
                checks.append(["app": app.bundleIdentifier ?? "", "front": front, "expected": expected, "actual": actual,
                               "lateOverrideInjected": inject, "windowMiniaturized": self.window.isMiniaturized,
                               "passed": front == app.bundleIdentifier && actual == expected && self.window.isMiniaturized])
                step(index + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { step(0) }
    }
    // Runs only on explicit developer request; restores configuration, input source and focus.
    func runIntegrationTest() {
        let saved = config; let originalSource = InputSources.currentID(); let originalApp = NSWorkspace.shared.frontmostApplication
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first!
        config.enabled = true; config.rules = [Rule(bundleID: "com.apple.finder", name: "Finder", mode: .traditional)]
        testEvents = []
        other.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { finder.activate(options: []) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { other.activate(options: []) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.config.rules.removeAll(); finder.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            let events = self.testEvents
            self.config = saved; self.activationWork?.cancel()
            self.config.enabled = false
            originalApp?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                try? InputSources.select(originalSource)
                let report: [String: Any] = ["events": events, "passed": events.count >= 3 && events.allSatisfy { $0["expected"] == $0["actual"] }]
                let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PinyinPilot-integration.json")
                try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try! data.write(to: url)
                NSApp.terminate(nil)
            }
        }
    }
}

if CommandLine.arguments.contains("--privacy-test") {
    // Local loopback only; never contacts an external host or sends user data.
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(9).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    let failure = errno
    close(fd)
    guard result == -1 && failure == EPERM else {
        print("FAIL: network sandbox denial not proven (result=\(result), errno=\(failure))"); exit(1)
    }
    print("PASS: sandbox blocked outbound socket with EPERM, including loopback")
} else if CommandLine.arguments.contains("--list-sources") {
    for source in InputSources.available() { print("\(source.id)\t\(source.name)") }
} else if CommandLine.arguments.contains("--self-test") {
    var config = Configuration()
    precondition(config.mode(for: "unknown") == .simplified)
    config.upsert(Rule(bundleID: "example", name: "Example", mode: .traditional))
    precondition(config.mode(for: "example") == .traditional)
    config.upsert(Rule(bundleID: "example", name: "Example", mode: .simplified))
    precondition(config.rules.count == 1 && config.mode(for: "example") == .simplified)
    config.rules.removeAll(); precondition(config.mode(for: "example") == .simplified)
    let suite = "PinyinPilot.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = Store(defaults: defaults)
    config.upsert(Rule(bundleID: "saved", name: "持久化", mode: .traditional))
    try store.save(config); let loaded = try store.load(); precondition(loaded == config)
    defaults.removePersistentDomain(forName: suite)
    print("PASS: default simplified, add, update, delete, Codable and local persistence")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
}
