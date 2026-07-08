import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    let craftService = CraftMCPService()

    private var statusItem:         NSStatusItem!
    private var capturePanel:       NSPanel?
    private var hotKeyRef:          EventHotKeyRef?
    private var globalEventMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        registerHotKey()

        // Load from cache immediately; refresh in background if stale
        Task { await craftService.loadDocuments() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let ref     = hotKeyRef          { UnregisterEventHotKey(ref) }
        if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "pencil.and.outline",
                               accessibilityDescription: "CraftQuickCapture")
        button.image?.isTemplate = true
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleStatusItemClick)
        button.target = self
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture rapide   ⌥⌘Space",
                                     action: #selector(openPanel), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Rafraîchir les documents",
                                     action: #selector(refreshDocuments), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Préférences…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter CraftQuickCapture",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshDocuments() {
        Task { await craftService.refreshDocuments() }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Panel

    private func togglePanel() {
        if capturePanel?.isVisible == true {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    @objc func openPanel() { showPanel() }

    func showPanel() {
        if capturePanel == nil { buildPanel() }
        positionPanel()
        capturePanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Dismiss when clicking outside
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissPanel()
        }

        // Refresh documents in background if cache is stale
        Task { await craftService.loadDocuments() }
    }

    func dismissPanel() {
        capturePanel?.orderOut(nil)
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    private func buildPanel() {
        let rootView = CaptureView(service: craftService,
                                   onDismiss: { [weak self] in self?.dismissPanel() })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 570),
            styleMask:   [.borderless, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        panel.backgroundColor           = .clear
        panel.isOpaque                  = false
        panel.hasShadow                 = true
        panel.level                     = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior        = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior         = .utilityWindow
        panel.contentView               = NSHostingView(rootView: rootView)
        capturePanel = panel
    }

    private func positionPanel() {
        guard let panel = capturePanel else { return }

        if let button = statusItem.button, let btnWin = button.window {
            let btnFrame  = button.convert(button.bounds, to: nil)
            let screenPt  = btnWin.convertToScreen(btnFrame)

            var x = screenPt.midX - panel.frame.width / 2
            let y = screenPt.minY - panel.frame.height - 8

            if let screen = NSScreen.main {
                x = max(screen.visibleFrame.minX + 8,
                        min(x, screen.visibleFrame.maxX - panel.frame.width - 8))
            }
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
    }

    // MARK: - Global Hotkey  ⌥⌘Space  (configurable in Settings)

    func registerHotKey() {
        // Unregister any existing hotkey
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, ctx) -> OSStatus in
                guard let ctx else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { delegate.showPanel() }
                return noErr
            },
            1, &spec, selfPtr, nil
        )

        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = fourCharCode("CQCP")
        hotkeyID.id = 1

        RegisterEventHotKey(
            craftService.config.hotkeyKeyCode,
            craftService.config.hotkeyModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

// MARK: - Helpers

private func fourCharCode(_ s: String) -> OSType {
    s.utf16.reduce(0) { ($0 << 8) + OSType($1) }
}
