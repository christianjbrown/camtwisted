import Foundation

/// Something whose published values are looked at again and again, and
/// changed only when they differ, so an idle refresh redraws nothing.
@MainActor
protocol QuietlyAssigning: AnyObject {}

extension QuietlyAssigning {
    func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
