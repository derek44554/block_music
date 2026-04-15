import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private var trayMenu: NSMenu?
  private var didSetupStatusItem = false

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    setupStatusItemIfNeeded()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupStatusItemIfNeeded()
    attachMainWindowDelegate()
    NSApp.setActivationPolicy(.accessory)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowDidBecomeMain(_:)),
      name: NSWindow.didBecomeMainNotification,
      object: nil
    )
    DispatchQueue.main.async { [weak self] in
      self?.setupStatusItemIfNeeded()
      self?.attachMainWindowDelegate()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 点击窗口关闭按钮后保留应用运行，让状态栏入口可用。
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // 关闭窗口时改为隐藏，避免应用退出。
    sender.isReleasedWhenClosed = false
    sender.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
    updatePrimaryMenuItemTitle()
    return false
  }

  @objc private func toggleMainWindow() {
    guard let window = mainWindow else { return }
    if window.isVisible {
      window.orderOut(nil)
      NSApp.setActivationPolicy(.accessory)
    } else {
      showMainWindow()
    }
    updatePrimaryMenuItemTitle()
  }

  @objc private func openMainWindowFromStatusItem() {
    showMainWindow()
    updatePrimaryMenuItemTitle()
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    guard let event = NSApp.currentEvent else {
      openMainWindowFromStatusItem()
      return
    }
    if event.type == .rightMouseUp {
      showStatusMenu()
    } else {
      openMainWindowFromStatusItem()
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  private func setupStatusItemIfNeeded() {
    if didSetupStatusItem { return }
    didSetupStatusItem = true

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.isVisible = true

    if let button = item.button {
      button.title = "♪"
      if #available(macOS 11.0, *) {
        button.image = NSImage(
          systemSymbolName: "music.note",
          accessibilityDescription: "BlockMusic"
        )
        button.image?.isTemplate = true
      }
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    let menu = NSMenu()
    menu.addItem(
      withTitle: "打开窗口",
      action: #selector(openMainWindowFromStatusItem),
      keyEquivalent: ""
    )
    menu.addItem(
      withTitle: "隐藏窗口",
      action: #selector(toggleMainWindow),
      keyEquivalent: ""
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
    menu.items.forEach { $0.target = self }
    trayMenu = menu
    updatePrimaryMenuItemTitle()
  }

  @objc private func showStatusMenu() {
    guard let item = statusItem, let menu = trayMenu else { return }
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  private func attachMainWindowDelegate() {
    mainWindow?.delegate = self
    updatePrimaryMenuItemTitle()
  }

  @objc private func handleWindowDidBecomeMain(_ notification: Notification) {
    (notification.object as? NSWindow)?.delegate = self
    updatePrimaryMenuItemTitle()
  }

  private var mainWindow: NSWindow? {
    if let key = NSApp.windows.first(where: { $0.isKeyWindow }) {
      return key
    }
    return NSApp.windows.first
  }

  private func showMainWindow() {
    guard let window = mainWindow else { return }
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func updatePrimaryMenuItemTitle() {
    guard let menu = trayMenu else { return }
    let showItem = menu.items.first
    let hideItem = menu.items.count > 1 ? menu.items[1] : nil
    let isVisible = mainWindow?.isVisible ?? false
    showItem?.isHidden = isVisible
    hideItem?.isHidden = !isVisible
  }
}
