import Foundation

/// Temporary CI diagnostics. Not for merge.
enum CIDebug {
    static let enabled = ProcessInfo.processInfo.environment["ANNOTATE_CI_DEBUG"] != nil
        || NSClassFromString("XCTestCase") != nil

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("CIDEBUG \(message())\n".utf8))
    }
}
