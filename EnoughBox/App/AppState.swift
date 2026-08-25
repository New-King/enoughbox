import Foundation
import SwiftUI

enum ToastStyle {
    case standard
    case error
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var installedPlugins: [InstalledPlugin] = []
    @Published var selectedPluginID: String?
    @Published var isPluginStorePresented = false
    @Published var toastMessage: String?
    @Published private(set) var toastStyle: ToastStyle = .standard
    @Published private(set) var installPhases: [String: PluginInstallPhase] = [:]

    private var toastGeneration = 0

    private(set) lazy var pluginManager = PluginManager { [weak self] message in
        self?.showToast(message)
    }

    private let registry = PluginRegistry.shared
    private let installer = PluginInstaller()

    var hasInstalledPlugins: Bool { !installedPlugins.isEmpty }

    var selectedPlugin: InstalledPlugin? {
        guard let selectedPluginID else { return nil }
        return installedPlugins.first { $0.id == selectedPluginID }
    }

    init() {
        installedPlugins = registry.load()
        selectedPluginID = installedPlugins.first?.id
        pluginManager.loadInstalled(installedPlugins)
    }

    func openPluginStore() {
        isPluginStorePresented = true
    }

    func installPhase(for pluginID: String) -> PluginInstallPhase? {
        installPhases[pluginID]
    }

    func install(_ storePlugin: StorePlugin) {
        guard !storePlugin.comingSoon else { return }
        guard !installedPlugins.contains(where: { $0.id == storePlugin.id }) else { return }
        guard installPhases[storePlugin.id]?.isBusy != true else { return }

        Task { await performInstall(storePlugin) }
    }

    func retryInstall(_ storePlugin: StorePlugin) {
        installPhases.removeValue(forKey: storePlugin.id)
        install(storePlugin)
    }

    func uninstall(_ plugin: InstalledPlugin) {
        guard installPhases[plugin.id]?.isBusy != true else { return }

        Task { await performUninstall(plugin) }
    }

    func isInstalled(_ storePlugin: StorePlugin) -> Bool {
        installedPlugins.contains { $0.id == storePlugin.id }
    }

    func displayName(for plugin: InstalledPlugin) -> String {
        if let runtime = pluginManager.runtime(for: plugin.id) {
            return runtime.localizedName()
        }
        switch plugin.id {
        case "com.enoughbox.sample":
            return String(localized: "plugin.sample.name")
        case "com.enoughbox.translate":
            return String(localized: "plugin.translate.name")
        default:
            return plugin.id
        }
    }

    func showToast(_ message: String, style: ToastStyle = .standard) {
        toastStyle = style
        toastMessage = message
        toastGeneration += 1
        let generation = toastGeneration
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastGeneration == generation {
                toastMessage = nil
            }
        }
    }

    private func performInstall(_ storePlugin: StorePlugin) async {
        installPhases[storePlugin.id] = .downloading(progress: 0)

        do {
            try await installer.install(storePlugin) { [weak self] phase in
                self?.installPhases[storePlugin.id] = phase
            }

            let plugin = InstalledPlugin(
                id: storePlugin.id,
                iconName: storePlugin.iconName,
                version: storePlugin.version,
                capabilities: storePlugin.capabilities
            )
            installedPlugins.append(plugin)
            selectedPluginID = plugin.id
            try registry.save(installedPlugins)
            pluginManager.load(pluginID: plugin.id)
            installPhases.removeValue(forKey: storePlugin.id)
        } catch {
            installPhases[storePlugin.id] = .failed(messageKey: "pluginStore.error.install")
        }
    }

    private func performUninstall(_ plugin: InstalledPlugin) async {
        installPhases[plugin.id] = .uninstalling

        do {
            pluginManager.unload(pluginID: plugin.id)
            HotkeyCenter.shared.clearSavedShortcuts(forPluginID: plugin.id)
            try await installer.uninstall(plugin)
            installedPlugins.removeAll { $0.id == plugin.id }
            if selectedPluginID == plugin.id {
                selectedPluginID = installedPlugins.first?.id
            }
            try registry.save(installedPlugins)
            installPhases.removeValue(forKey: plugin.id)
        } catch {
            installPhases[plugin.id] = .failed(messageKey: "pluginStore.error.uninstall")
        }
    }

    #if DEBUG
    static var previewPopulated: AppState {
        let state = AppState()
        if state.installedPlugins.isEmpty {
            state.installedPlugins = [
                InstalledPlugin(
                    id: "com.enoughbox.sample",
                    iconName: "puzzlepiece.extension",
                    version: "0.1.0",
                    capabilities: [.hotkey, .clipboard]
                ),
            ]
            state.selectedPluginID = state.installedPlugins.first?.id
        }
        return state
    }
    #endif
}
