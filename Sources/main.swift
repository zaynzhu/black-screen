import Cocoa
import ApplicationServices

// 全屏黑屏窗口：必须能成为 key window，才能接收 ESC
final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

// 管理每块屏幕上的黑色覆盖窗口
final class BlackScreenController {
  private var windows: [NSWindow] = []
  private var keyMonitor: Any?
  private var globalKeyMonitor: Any?
  private var activeObserver: NSObjectProtocol?
  private var previousApp: NSRunningApplication?
  private(set) var isShowing = false

  func show() {
    guard !isShowing else { return }
    isShowing = true

    // 记住黑屏前的前台应用，退出后把焦点还回去
    let frontmost = NSWorkspace.shared.frontmostApplication
    if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
      previousApp = frontmost
    }

    for screen in NSScreen.screens {
      let window = OverlayWindow(
        contentRect: screen.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false,
        screen: screen
      )
      window.backgroundColor = .black
      window.isOpaque = true
      window.hasShadow = false
      window.level = .screenSaver
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      // 吃掉鼠标点击，避免在黑屏时误触下层应用
      window.ignoresMouseEvents = false
      window.orderFrontRegardless()
      windows.append(window)
    }

    // 先让窗口成为 key，再激活 App，确保键盘事件能送进来
    windows.first?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    windows.first?.makeKey()
    NSCursor.hide()

    // 其他 App 抢走焦点时立刻抢回来，否则 ESC 会失效
    activeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.isShowing else { return }
        NSApp.activate(ignoringOtherApps: true)
        self.windows.first?.makeKey()
      }
    }

    // 本地键盘监听：ESC 或 Cmd+Q 退出
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let isEscape = event.keyCode == 53
      let isCommandQ = event.modifierFlags.contains(.command)
        && event.charactersIgnoringModifiers?.lowercased() == "q"

      if isEscape || isCommandQ {
        self?.hide()
        return nil
      }
      return event
    }

    // 授予辅助功能权限后，即使焦点被其他 App 抢走，也能收到 ESC
    if AXIsProcessTrusted() {
      globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53 else { return }
        DispatchQueue.main.async {
          self?.hide()
        }
      }
    }
  }

  func hide() {
    guard isShowing else { return }
    isShowing = false

    if let activeObserver {
      NotificationCenter.default.removeObserver(activeObserver)
      self.activeObserver = nil
    }

    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }

    if let globalKeyMonitor {
      NSEvent.removeMonitor(globalKeyMonitor)
      self.globalKeyMonitor = nil
    }

    for window in windows {
      window.orderOut(nil)
    }
    windows.removeAll()

    // 恢复鼠标指针
    NSCursor.unhide()
    NSCursor.arrow.set()

    // 把焦点还给黑屏前的应用
    previousApp?.activate(options: [])
    previousApp = nil
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var rightClickMonitor: Any?
  private let blackScreen = BlackScreenController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // 只驻留状态栏，不显示 Dock 图标
    NSApp.setActivationPolicy(.accessory)

    // macOS 26 默认把第三方状态项排在左侧，Chrome 这类宽菜单应用会把它盖住。
    // 首次运行给一个靠右的默认位置，之后尊重用户手动调整。
    let positionKey = "NSStatusItem Preferred Position Item-0"
    if UserDefaults.standard.object(forKey: positionKey) == nil {
      UserDefaults.standard.set(1400, forKey: positionKey)
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = statusItem.button else { return }

    let icon = NSImage(systemSymbolName: "display", accessibilityDescription: "黑屏")
      ?? NSImage(systemSymbolName: "rectangle.fill", accessibilityDescription: "黑屏")
    icon?.isTemplate = true
    button.image = icon
    if icon == nil {
      button.title = "黑"
    }
    button.toolTip = "一键黑屏（ESC 退出）"
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp])

    // NSStatusBarButton 不会把右键事件派发给 action，这里单独监听右键
    rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) { [weak self] event in
      guard let self, let button = self.statusItem.button, let window = button.window else {
        return event
      }
      let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
      if buttonRect.contains(NSEvent.mouseLocation) {
        self.showMenu()
        return nil
      }
      return event
    }

    if CommandLine.arguments.contains("--request-accessibility") {
      requestAccessibility()
    }
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    let event = NSApp.currentEvent
    let isRightClick = event?.type == .rightMouseUp
      || (event?.modifierFlags.contains(.control) ?? false)

    if isRightClick {
      showMenu()
    } else {
      blackScreen.show()
    }
  }

  private func showMenu() {
    let menu = NSMenu()

    let blackItem = NSMenuItem(title: "立即黑屏", action: #selector(showBlackScreen), keyEquivalent: "")
    blackItem.target = self
    menu.addItem(blackItem)

    let accessibilityItem: NSMenuItem
    if AXIsProcessTrusted() {
      accessibilityItem = NSMenuItem(title: "可靠 ESC 已启用（辅助功能）", action: nil, keyEquivalent: "")
      accessibilityItem.isEnabled = false
    } else {
      accessibilityItem = NSMenuItem(
        title: "启用可靠 ESC（辅助功能）…",
        action: #selector(requestAccessibility),
        keyEquivalent: ""
      )
      accessibilityItem.target = self
    }
    menu.addItem(accessibilityItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "退出 BlackScreen", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func showBlackScreen() {
    blackScreen.show()
  }

  @objc private func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
