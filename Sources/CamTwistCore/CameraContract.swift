import CoreGraphics
import Foundation

/// The fixed contract between the host app and the camera extension.
///
/// Both sides are built from this one definition and must agree exactly: the
/// app looks the device up by these identifiers and pushes frames in this
/// format, and the extension advertises the same format to every other app.
/// They are constants rather than configuration because a mismatch between
/// the two binaries cannot be repaired at run time.
public enum CameraContract {
    /// The app's own name.
    public static let deviceName = "CamTwisted"
    /// What other apps see in their list of cameras.
    public static let cameraName = "CamTwisted Virtual Camera output"
    public static let deviceModel = "CamTwisted Virtual Camera"
    public static let manufacturer = "CamTwisted"

    public static let deviceID = UUID(uuidString: "527C0239-66C7-4E9C-A8CA-AFFD0337A864")!
    public static let sourceStreamID = UUID(uuidString: "37D56EBF-21DE-4DB6-AFA0-7E0C0CB3024F")!
    public static let sinkStreamID = UUID(uuidString: "C48BF76E-4D12-49FF-86D3-20E784EB8BBB")!

    public static let sourceStreamName = "CamTwisted Video"
    public static let sinkStreamName = "CamTwisted Video Input"

    public static let width = 1920
    public static let height = 1080
    public static let framesPerSecond = 30

    /// Position of each stream in the device's stream list, in the order the
    /// extension adds them.
    public static let sourceStreamIndex = 0
    public static let sinkStreamIndex = 1

    /// Frames the sink holds before the extension has consumed them.
    public static let sinkQueueSize = 1
    public static let sinkBuffersRequiredForStartup = 1

    /// One pixel drawn for each point of the layout.
    public static let unitScale = 1

    public static var size: CGSize {
        CGSize(width: width, height: height)
    }
}

/// How the camera extension tells the app which apps have its picture
/// open: a property of the device holding their process numbers.
public enum CameraWatchers {
    /// The four characters the property is known by.
    public static let code = "wtch"
    /// The property as the extension declares it: its code, for the whole
    /// device, on its main element.
    public static let extensionProperty = "4cc_\(code)_glob_0000"
    private static let separator = ","
    private static let bitsPerCharacter: UInt32 = 8

    /// The property's code as the number Core Media I/O asks for it by.
    public static var selector: UInt32 {
        code.unicodeScalars.reduce(0) { $0 << bitsPerCharacter | $1.value }
    }

    /// The process numbers as the text the property carries.
    public static func text(for processes: [Int32]) -> String {
        processes.sorted().map(String.init).joined(separator: separator)
    }

    /// The process numbers in the property's text. Anything that is not a
    /// number is left out.
    public static func processes(in text: String) -> [Int32] {
        text.split(separator: Character(separator)).compactMap { Int32($0) }
    }
}

/// How much detail the finished picture is drawn with. Everything is laid
/// out the same either way; the larger size draws it with twice as many
/// pixels each way.
public enum DrawingSize: String, Codable, CaseIterable, Sendable {
    case fullHD
    case ultraHD

    /// How many pixels are drawn for each point of the layout, each way.
    public var scale: Int {
        switch self {
        case .fullHD: return 1
        case .ultraHD: return Self.doubled
        }
    }

    public var width: Int { CameraContract.width * scale }
    public var height: Int { CameraContract.height * scale }

    private static let doubled = 2
}
