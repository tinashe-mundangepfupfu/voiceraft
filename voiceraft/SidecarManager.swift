import Foundation

actor SidecarManager {
    private var process: Process?

    func processMeeting(session: MeetingSession, audioURL: URL, settings: AppSettings, endedAt: Date) async throws -> WorkflowResponsePayload {
        try await ensureRunning(settings: settings)
        let request = try buildRequestPayload(session: session, audioURL: audioURL, endedAt: endedAt)
        return try await sendRequest(request, settings: settings)
    }

    private func ensureRunning(settings: AppSettings) async throws {
        if try await healthcheck(settings: settings) {
            return
        }

        try launchSidecar(settings: settings)

        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(300))
            if try await healthcheck(settings: settings) {
                return
            }
            if let process, !process.isRunning {
                throw VoiceRaftError.sidecarLaunchFailed("The process exited before it became healthy.")
            }
        }

        throw VoiceRaftError.sidecarLaunchFailed("Timed out waiting for the sidecar to become healthy.")
    }

    private func launchSidecar(settings: AppSettings) throws {
        if let process, process.isRunning {
            return
        }

        let rootPath = settings.projectRootPath.isEmpty ? FileManager.default.currentDirectoryPath : settings.projectRootPath
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let executableURL = rootURL.appendingPathComponent(".venv/bin/voiceraft-sidecar")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw VoiceRaftError.sidecarExecutableMissing(executableURL.path)
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = rootURL

        var environment = ProcessInfo.processInfo.environment
        environment["VOICERAFT_HOST"] = settings.sidecarHost
        environment["VOICERAFT_PORT"] = "\(settings.sidecarPort)"
        environment["VOICERAFT_LM_STUDIO_BASE_URL"] = settings.lmStudioBaseURL
        environment["VOICERAFT_LM_STUDIO_MODEL"] = settings.lmStudioModel
        environment["VOICERAFT_WHISPER_MODEL"] = settings.whisperModel
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw VoiceRaftError.sidecarLaunchFailed(error.localizedDescription)
        }

        self.process = process
    }

    private func healthcheck(settings: AppSettings) async throws -> Bool {
        let url = try baseURL(settings: settings).appendingPathComponent("health")
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func sendRequest(_ payload: ProcessingRequestPayload, settings: AppSettings) async throws -> WorkflowResponsePayload {
        let url = try baseURL(settings: settings).appendingPathComponent("process")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceRaftError.sidecarRequestFailed("The sidecar returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VoiceRaftError.sidecarRequestFailed(body)
        }

        return try JSONDecoder().decode(WorkflowResponsePayload.self, from: data)
    }

    private func buildRequestPayload(session: MeetingSession, audioURL: URL, endedAt: Date) throws -> ProcessingRequestPayload {
        ProcessingRequestPayload(
            sessionID: session.id,
            audioPath: audioURL.path,
            meetingTitle: session.title,
            meetingMode: session.mode.rawValue,
            language: "en",
            startedAt: session.startedAt.voiceraftISO8601String(),
            endedAt: endedAt.voiceraftISO8601String()
        )
    }

    private func baseURL(settings: AppSettings) throws -> URL {
        guard let url = URL(string: "http://\(settings.sidecarHost):\(settings.sidecarPort)") else {
            throw VoiceRaftError.invalidSidecarBaseURL
        }
        return url
    }
}
