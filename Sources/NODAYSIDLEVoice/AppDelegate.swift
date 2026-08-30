import AppKit
import SwiftData
import SwiftUI

private final class VoicePanel: NSPanel {
    var permitsKey = false
    override var canBecomeKey: Bool { permitsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var controlPanel: NSPanel?
    private var hudPanel: NSPanel?
    private var previewPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var container: ModelContainer?
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePanels()
        connectPanels()

        do {
            let container = try VoiceData.makeContainer()
            self.container = container
            let coordinator = AppCoordinator(model: model, container: container)
            self.coordinator = coordinator
            coordinator.start()
        } catch {
            model.recordingState = .failed(.providerUnavailable)
            model.statusMessage = "Local data could not be opened: \(error.localizedDescription)"
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "nodaysidlevoice" }) else { return }
        togglePanel()
    }

    @objc func togglePanel() {
        guard let controlPanel else { return }
        if controlPanel.isVisible {
            controlPanel.orderOut(nil)
        } else {
            position(controlPanel, atTopRightWith: 18)
            controlPanel.orderFrontRegardless()
        }
    }

    private func connectPanels() {
        model.controlCenterHandler = { [weak self] in self?.togglePanel() }
        model.settingsHandler = { [weak self] in self?.showSettings($0) }
        model.hudVisibilityHandler = { [weak self] visible in
            visible ? self?.showHUD() : self?.hudPanel?.orderOut(nil)
        }
        model.hudWidthHandler = { [weak self] width in self?.resizeHUD(to: width) }
        model.previewHandler = { [weak self] visible in self?.showPreview(visible) }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let fallback = NSImage(
            systemSymbolName: "n.square.fill",
            accessibilityDescription: "NODAYSIDLE Voice Control Center"
        )
        let image = Bundle.main.url(forResource: "MenuBarN", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:)) ?? fallback
        image?.size = NSSize(width: 17, height: 17)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.setAccessibilityLabel("NODAYSIDLE Voice Control Center")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = "NODAYSIDLE Voice"
        statusItem = item
    }

    private func configurePanels() {
        controlPanel = makePanel(
            identifier: "control-center",
            title: "NODAYSIDLE Voice Control Center",
            size: NSSize(width: 380, height: 520),
            rootView: MenuPanelView().environment(model).preferredColorScheme(model.appearance.colorScheme),
            permitsKey: false
        )
        hudPanel = makePanel(
            identifier: "capsule",
            title: "NODAYSIDLE Voice Capsule",
            size: NSSize(width: 144, height: 48),
            rootView: RecordingHUDView().environment(model).preferredColorScheme(model.appearance.colorScheme),
            permitsKey: false
        )
        previewPanel = makePanel(
            identifier: "preview",
            title: "Review Transcript",
            size: NSSize(width: 540, height: 330),
            rootView: TranscriptPreviewView().environment(model).preferredColorScheme(model.appearance.colorScheme),
            permitsKey: true
        )
        settingsWindow = makeSettingsWindow()
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 980, height: 680)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.title = "NODAYSIDLE Voice Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: SettingsView().environment(model))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = NSSize(width: 820, height: 580)
        window.center()
        return window
    }

    private func makePanel<Content: View>(
        identifier: String,
        title: String,
        size: NSSize,
        rootView: Content,
        permitsKey: Bool
    ) -> NSPanel {
        let panel = VoicePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.permitsKey = permitsKey
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        panel.title = title
        panel.contentView = NSHostingView(rootView: rootView)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .utilityWindow
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func showHUD() {
        guard let hudPanel else { return }
        positionHUD(hudPanel)
        hudPanel.orderFrontRegardless()
    }

    private func resizeHUD(to width: CGFloat) {
        guard let hudPanel else { return }
        let origin = hudPanel.frame.origin
        hudPanel.setContentSize(NSSize(width: width, height: 48))
        if hudPanel.isVisible {
            hudPanel.setFrameOrigin(NSPoint(x: origin.x - (width - hudPanel.frame.width) / 2, y: origin.y))
            positionHUD(hudPanel)
        }
    }

    private func showPreview(_ visible: Bool) {
        guard let previewPanel else { return }
        if visible {
            positionAtCenter(previewPanel)
            NSApp.activate(ignoringOtherApps: true)
            previewPanel.makeKeyAndOrderFront(nil)
        } else {
            previewPanel.orderOut(nil)
        }
    }

    private func showSettings(_ page: SettingsPage) {
        guard let settingsWindow else { return }
        model.selectedSettingsPage = page
        controlPanel?.orderOut(nil)
        if !settingsWindow.isVisible { settingsWindow.center() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func positionHUD(_ panel: NSPanel) {
        let visible = activeScreen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 28
        ))
    }

    private func positionAtCenter(_ panel: NSPanel) {
        let visible = activeScreen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.midY - panel.frame.height / 2
        ))
    }

    private func position(_ panel: NSPanel, atTopRightWith inset: CGFloat) {
        let visible = activeScreen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - inset,
            y: visible.maxY - panel.frame.height - inset
        ))
    }

    private var activeScreen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
