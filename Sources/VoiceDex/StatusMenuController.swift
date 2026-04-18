import AppKit

@MainActor
final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateItem = NSMenuItem(title: "State: idle", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let openSettingsHandler: () -> Void
    private let openConfigHandler: () -> Void
    private let quitHandler: () -> Void

    init(
        openSettingsHandler: @escaping () -> Void,
        openConfigHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.openSettingsHandler = openSettingsHandler
        self.openConfigHandler = openConfigHandler
        self.quitHandler = quitHandler
        super.init()
        configureMenu()
        update(state: .ready, detail: "Ready. Press F5 to dictate")
    }

    func update(state: StatusMenuVisualState, detail: String) {
        if let button = statusItem.button {
            button.title = ""
            button.image = ChatTypeStatusIconRenderer.image(for: state)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("ChatType \(state.stateDescription)")
            button.toolTip = "ChatType: \(state.stateDescription)"
        }

        stateItem.title = "State: \(state.stateDescription)"
        detailItem.title = detail
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(detailItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let openConfigItem = NSMenuItem(
            title: "Open Config Folder",
            action: #selector(openConfigFolder),
            keyEquivalent: ""
        )
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        let quitItem = NSMenuItem(
            title: "Quit ChatType",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func openSettings() {
        openSettingsHandler()
    }

    @objc
    private func openConfigFolder() {
        openConfigHandler()
    }

    @objc
    private func quitApp() {
        quitHandler()
    }
}
