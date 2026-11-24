import CamTwistCore
import CoreMediaIO
import Foundation

let providerSource = CameraExtensionAssembly(pacing: Pacing.load(defaults: .standard), clock: Date.init)
    .makeProviderSource()
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
