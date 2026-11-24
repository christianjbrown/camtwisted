import CamTwistControl
import Foundation

struct AppleScriptRunner: ScriptRunning {
    func run(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
