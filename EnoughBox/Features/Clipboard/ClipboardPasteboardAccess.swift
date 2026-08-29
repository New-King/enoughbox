import Foundation

/// Serializes background reads and writes of the general pasteboard.
enum ClipboardPasteboardAccess {
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let queueValue: UInt8 = 1
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.enoughbox.clipboard.pasteboard", qos: .utility)
        queue.setSpecific(key: queueKey, value: queueValue)
        return queue
    }()

    static func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    static func sync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == queueValue {
            return try work()
        }
        return try queue.sync(execute: work)
    }
}
