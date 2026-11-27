import Foundation

/// The end of what has been said: the words that are settled, then the
/// ones still being worked out. Only the end is kept, since captions only
/// ever show their last few lines.
public struct TranscriptTail: Equatable, Sendable {
    /// Far more than the most captions can show at once.
    public static let keptCharacters = 400

    private var settled = ""
    private var pending = ""

    public init() {}

    /// Takes a result: one that is final settles its words, and one that
    /// is not stands in for whatever is still being worked out.
    public mutating func take(_ text: String, isFinal: Bool) {
        if isFinal {
            settled = Self.tail(of: Self.joined(settled, text))
            pending = ""
        } else {
            pending = text
        }
    }

    public var words: String {
        Self.tail(of: Self.joined(settled, pending))
    }

    private static func joined(_ first: String, _ second: String) -> String {
        [first, second].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The last characters, starting at a word so none is cut in half.
    private static func tail(of text: String) -> String {
        guard text.count > keptCharacters else { return text }
        let end = String(text.suffix(keptCharacters))
        guard let space = end.firstIndex(of: " ") else { return end }
        return String(end[end.index(after: space)...])
    }
}
