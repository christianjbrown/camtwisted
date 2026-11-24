import CamTwistCore
import CamTwistRendering
import Foundation

/// The passwords of the computers whose screens are shown over VNC.
public struct RemoteScreenPasswords {
    private let passwords: PasswordKeeping

    init(passwords: PasswordKeeping) {
        self.passwords = passwords
    }

    /// The VNC password kept for a computer, when there is one.
    public func password(for settings: VNCSettings) -> String? {
        passwords.password(for: settings.account)
    }

    /// Keeps a computer's VNC password in the keychain. An empty one is forgotten.
    public func setPassword(_ password: String, for settings: VNCSettings) {
        passwords.setPassword(password, for: settings.account)
    }
}
