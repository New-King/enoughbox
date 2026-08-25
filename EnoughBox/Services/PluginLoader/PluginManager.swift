import AppKit
import EnoughBoxPluginSDK
import Foundation

struct LoadedPluginRuntime: Identifiable {
    let id: String
    let instance: EnoughBoxPlugin
    let bundle: Bundle

    var iconName: String { instance.iconName }
    var version: String { instance.version }

    func localizedName(for locale: Locale = .current) -> String {
        instance.localizedName(for: locale)
    }
}

@MainActor
final class PluginManager: ObservableObject {
    @Published private(set) var runtimes: [String: LoadedPluginRuntime] = [:]

    private let hostServices: HostServicesImpl

    init(toastHandler: @escaping (String) -> Void) {
        hostServices = HostServicesImpl(toastHandler: toastHandler)
    }

    func runtime(for id: String) -> LoadedPluginRuntime? {
        runtimes[id]
    }

    func loadInstalled(_ plugins: [InstalledPlugin]) {
        for plugin in plugins {
            load(pluginID: plugin.id)
        }
    }

    func load(pluginID: String) {
        guard runtimes[pluginID] == nil else { return }

        let destination = PluginLoader.bundleURL(forPluginID: pluginID)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }

        do {
            let (instance, bundle) = try PluginLoader.load(from: destination, host: hostServices)
            runtimes[pluginID] = LoadedPluginRuntime(id: pluginID, instance: instance, bundle: bundle)
        } catch {
            NSLog("EnoughBox: failed to load plugin \(pluginID): \(error.localizedDescription)")
        }
    }

    func unload(pluginID: String) {
        guard let runtime = runtimes.removeValue(forKey: pluginID) else { return }
        PluginLoader.unload(runtime.instance, bundle: runtime.bundle)
    }

    func settingsViewController(for pluginID: String) -> NSViewController? {
        guard let runtime = runtimes[pluginID] else { return nil }
        return runtime.instance.makeSettingsViewController(host: hostServices)
    }
}
