import AppKit

enum StatusItemState {
    case idle
    case recording
    case processing
}

struct StatusItemAppearance {
    let title: String
    let symbolName: String
    let tintColor: NSColor

    static func make(for state: StatusItemState) -> StatusItemAppearance {
        switch state {
        case .idle:
            StatusItemAppearance(title: "", symbolName: VoiceRaftStatusItemIcon.splitVGlyphName, tintColor: .white)
        case .recording:
            StatusItemAppearance(title: "", symbolName: VoiceRaftStatusItemIcon.splitVGlyphName, tintColor: .systemRed)
        case .processing:
            StatusItemAppearance(title: "", symbolName: VoiceRaftStatusItemIcon.splitVGlyphName, tintColor: .systemOrange)
        }
    }
}

extension CoordinatorState {
    var statusItemAppearance: StatusItemAppearance {
        switch self {
        case .idle:
            StatusItemAppearance.make(for: .idle)
        case .recording:
            StatusItemAppearance.make(for: .recording)
        case .processing:
            StatusItemAppearance.make(for: .processing)
        }
    }
}
