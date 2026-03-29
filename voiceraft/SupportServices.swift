import AppKit
@preconcurrency import AVFoundation
import Foundation
import UserNotifications

struct AudioInputDeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AudioInputDeviceCatalog {
    static func availableDevices() -> [AudioInputDeviceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { AudioInputDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum FileLayout {
    static func applicationSupportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("VoiceRaft", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func timestampedFilename(for session: MeetingSession) -> String {
        "\(filenameTimestampFormatter.string(from: session.startedAt)) - \(sanitizeFilename(session.title)).md"
    }

    static func timestampedAudioFilename(for session: MeetingSession) -> String {
        "\(filenameTimestampFormatter.string(from: session.startedAt)) - \(sanitizeFilename(session.title)).m4a"
    }

    static func meetingsFolder(in vaultRoot: URL, startedAt: Date) -> URL {
        let year = yearFormatter.string(from: startedAt)
        let month = monthFormatter.string(from: startedAt)
        return vaultRoot
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
    }

    static func sanitizeFilename(_ raw: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalidCharacters).joined(separator: " ")
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Meeting" : trimmed
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM"
        return formatter
    }()
}

extension Date {
    func voiceraftISO8601String() -> String {
        Self.isoFormatter.string(from: self)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

@MainActor
final class NotificationPresenter {
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    private let center: UNUserNotificationCenter

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}

struct ObsidianVaultWriter {
    func write(markdown: String, session: MeetingSession, vaultPath: String) throws -> URL {
        guard !vaultPath.isEmpty else {
            throw VoiceRaftError.missingOrInvalidVaultPath
        }

        let root = URL(fileURLWithPath: vaultPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VoiceRaftError.missingOrInvalidVaultPath
        }

        let folder = FileLayout.meetingsFolder(in: root, startedAt: session.startedAt)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileURL = folder.appendingPathComponent(FileLayout.timestampedFilename(for: session))
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw VoiceRaftError.exportFailed(error.localizedDescription)
        }
        return fileURL
    }
}

struct PendingExportStore {
    func save(markdown: String, session: MeetingSession) throws -> URL {
        let directory = try FileLayout.applicationSupportDirectory().appendingPathComponent("PendingExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(FileLayout.timestampedFilename(for: session))
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw VoiceRaftError.pendingExportFailed(error.localizedDescription)
        }
    }
}
