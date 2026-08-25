import EnoughBoxPluginSDK
import Foundation

enum PluginLoaderError: LocalizedError {
    case bundleNotFound(URL)
    case loadFailed(URL, String)
    case missingPrincipalClass(String)

    var errorDescription: String? {
        switch self {
        case let .bundleNotFound(url):
            return "Plugin bundle not found at \(url.path)"
        case let .loadFailed(url, reason):
            return "Failed to load \(url.lastPathComponent): \(reason)"
        case let .missingPrincipalClass(name):
            return "Missing principal class \(name)"
        }
    }
}

enum PluginLoader {
    static func bundleURL(forPluginID id: String) -> URL {
        AppPaths.pluginsDirectory.appendingPathComponent("\(id).plugin", isDirectory: true)
    }

    @MainActor
    static func load(from bundleURL: URL, host: HostServices) throws -> (EnoughBoxPlugin, Bundle) {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw PluginLoaderError.bundleNotFound(bundleURL)
        }

        guard let bundle = Bundle(url: bundleURL) else {
            throw PluginLoaderError.loadFailed(bundleURL, "Invalid bundle URL")
        }

        do {
            try bundle.loadAndReturnError()
        } catch {
            throw PluginLoaderError.loadFailed(bundleURL, error.localizedDescription)
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            throw PluginLoaderError.missingPrincipalClass(bundleURL.lastPathComponent)
        }

        guard let instance = principalClass.init() as? EnoughBoxPlugin else {
            throw PluginLoaderError.missingPrincipalClass(bundleURL.lastPathComponent)
        }
        instance.activate(host: host)
        return (instance, bundle)
    }

    @MainActor
    static func unload(_ instance: EnoughBoxPlugin, bundle: Bundle) {
        instance.deactivate()
        bundle.unload()
    }
}
