enum RecordingWriterState: Equatable {
    case waitingForFirstSample
    case writing
    case failed(String?)
    case cancelled
}

enum RecordingStopAction: Equatable {
    case discardEmptyRecording
    case finishWriting
    case fail(String)
}

enum RecordingStopPolicy {
    static func action(for state: RecordingWriterState) -> RecordingStopAction {
        switch state {
        case .waitingForFirstSample:
            .discardEmptyRecording
        case .writing:
            .finishWriting
        case let .failed(message):
            .fail(message ?? "The recording writer failed before VoiceRaft could finish the file.")
        case .cancelled:
            .fail("The recording was cancelled before VoiceRaft could finish the file.")
        }
    }
}
