import CamTwistControl
import CamTwistCore
import CamTwistRendering
import Foundation

extension AppAssembly {
    /// The effects and transitions there are to pick from.
    struct EffectSet {
        let supplies: RenderingSupplies
        let transitions: NativeTransitionLibrary
        let library: CombinedEffectLibrary

        init(_ basics: Basics) {
            let configuration = basics.configuration
            let pacing = basics.pacing
            supplies = RenderingSupplies.system()
            transitions = BuiltInEffects.transitionLibrary(directory: configuration.effectsDirectory)
            // Built-in effects and transitions come first, so one takes the
            // place of a file of the same name.
            library = CombinedEffectLibrary(
                primary: BuiltInEffects.library(
                    directory: configuration.effectsDirectory, tuning: configuration.tunables.effects,
                    supplies: supplies
                ),
                others: [
                    transitions,
                    HTMLEffectLibrary(
                        directory: configuration.effectsDirectory, snapshotsPerSecond: pacing.websiteSnapshotsPerSecond,
                        timers: basics.timers, listing: FileManagerDirectoryListing(),
                        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
                    ),
                    HTMLEffectLibrary(
                        directory: configuration.bundledWebEffectsDirectory,
                        snapshotsPerSecond: pacing.websiteSnapshotsPerSecond,
                        timers: basics.timers, listing: FileManagerDirectoryListing(),
                        onMain: RenderingSystem.mainHop, makeHost: RenderingSystem.makeWebPageHost
                    ),
                ]
            )
        }
    }
}
