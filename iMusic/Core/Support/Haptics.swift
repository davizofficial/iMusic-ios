import UIKit

/// Feedback generators, kept stateless and cheap. Generators are prepared on
/// use because playback is low-frequency (plan §6.4).
enum Haptics {
    static func play() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
