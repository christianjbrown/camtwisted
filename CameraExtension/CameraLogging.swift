import os.log

/// Where the extension reports what went wrong.
protocol CameraLogger {
    func error(_ message: String)
}

/// Writes to the unified log.
struct OSCameraLogger: CameraLogger {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
