import Foundation

public enum EasyNativeLogLevel: String {
    case debug
    case info
    case warning
    case error
}

public final class EasyNativeLogger {
    public typealias Provider = (_ level: EasyNativeLogLevel, _ message: String, _ error: Error?) -> Void

    public static var provider: Provider?
    public static var enabled = true

    private init() {}

    public static func log(_ level: EasyNativeLogLevel, _ message: String, error: Error? = nil) {
        guard enabled else {
            return
        }
        if let provider = provider {
            provider(level, message, error)
            return
        }
        if let error = error {
            print("[EasyNative][\(level.rawValue)] \(message) error=\(error)")
        } else {
            print("[EasyNative][\(level.rawValue)] \(message)")
        }
    }
}
