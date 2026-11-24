import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

/// Shared plumbing for the AppleScript commands.
class CamTwistScriptCommand: NSScriptCommand {
    /// The direct parameter as text: plain text, or the name of the object
    /// a specifier such as `studioButton "Wide"` points at.
    var directName: String? {
        if let text = directParameter as? String { return text }
        return (directObject as? NSObject)?.value(forKey: Self.nameKey) as? String
    }

    var directEffect: ScriptEffect? {
        directObject as? ScriptEffect
    }

    /// The object the command names. Cocoa files an object direct parameter
    /// under the receivers, so both places are checked.
    private var directObject: Any? {
        let specifier = (directParameter as? NSScriptObjectSpecifier) ?? receiversSpecifier
        return specifier?.objectsByEvaluatingSpecifier
    }

    /// Cocoa would otherwise send a command whose direct parameter is an
    /// object, such as `click studioButton "Wide"`, to that object. These
    /// commands all act on the app, so they run here instead.
    override func execute() -> Any? {
        performDefaultImplementation()
    }

    @MainActor var scenes: ScriptedScenes? { ScriptingBridge.shared.scenes }
    @MainActor var actions: ScriptActing? { ScriptingBridge.shared.actions }
    @MainActor var sources: ScriptSourceFinding? { ScriptingBridge.shared.sources }
    @MainActor var snapshots: ScriptSnapshotting? { ScriptingBridge.shared.snapshots }

    @MainActor func perform(_ action: TriggerAction) {
        ScriptingBridge.shared.perform(action)
    }

    /// Reports a failure back to the script that sent the command.
    func fail(_ message: String) {
        scriptErrorNumber = Self.genericScriptError
        scriptErrorString = message
    }

    private static let nameKey = "name"
    /// AppleScript's general "the command failed" error number.
    private static let genericScriptError = -10000
}

@objc(CTAddEffectCommand)
final class AddEffectCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { actions?.addStep(.effect(name: name, values: [:])) }
        return nil
    }
}

@objc(CTSetSourceCommand)
final class SetSourceCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName, let spec = sources?.sourceSpec(named: name) {
            scenes?.scene.setMainSource(spec)
        }
        return nil
    }
}

@objc(CTSetPropertyCommand)
final class SetPropertyCommand: CamTwistScriptCommand {
    private static let propertyKey = "property"
    private static let valueKey = "value"

    @MainActor override func performDefaultImplementation() -> Any? {
        guard let effect = directEffect else {
            fail("That effect is not in use.")
            return nil
        }
        guard let property = evaluatedArguments?[Self.propertyKey] as? String,
              let value = evaluatedArguments?[Self.valueKey] as? String
        else {
            fail("setprop needs a property name and a value.")
            return nil
        }
        if actions?.setEffectProperty(property, to: value, ofStep: effect.id) != true {
            fail("\(effect.name) has no property called \(property).")
        }
        return nil
    }
}

@objc(CTSelectTransitionCommand)
final class SelectTransitionCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { scenes?.studio.choose(transition: name) }
        return nil
    }
}

@objc(CTSelectForAirCommand)
final class SelectForAirCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { perform(.studioPreview(button: name)) }
        return nil
    }
}

@objc(CTPunchToAirCommand)
final class PunchToAirCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { perform(.studioPunch(button: name)) }
        return nil
    }
}

@objc(CTDeleteButtonCommand)
final class DeleteButtonCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { scenes?.studio.removeButtons(named: name) }
        return nil
    }
}

@objc(CTDuplicateButtonCommand)
final class DuplicateButtonCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        if let name = directName { scenes?.studio.appendDuplicate(ofButtonNamed: name) }
        return nil
    }
}

@objc(CTStartTransitionCommand)
final class StartTransitionCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        perform(.studioTransition)
        return nil
    }
}

@objc(CTCutCommand)
final class CutCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        perform(.studioCut)
        return nil
    }
}

@objc(CTDissolveCommand)
final class DissolveCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        scenes?.studio.choose(transition: DissolveTransition.name)
        perform(.studioTransition)
        return nil
    }
}

@objc(CTSnapshotCommand)
final class SnapshotCommand: CamTwistScriptCommand {
    @MainActor override func performDefaultImplementation() -> Any? {
        guard let url = snapshots?.writeSnapshot() else {
            fail("The snapshot could not be saved.")
            return nil
        }
        return url.path
    }
}
