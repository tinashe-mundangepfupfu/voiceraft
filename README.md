<p align="center">
  <img src="docs/assets/readme-header.svg" alt="VoiceRaft banner showing a Swift-native macOS meeting workflow with local capture, polished notes, and Obsidian export.">
</p>

VoiceRaft is a macOS menu-bar app that captures meeting audio, transcribes it locally with Apple's Speech framework, refines structured notes through LM Studio, and exports the finished markdown into an Obsidian vault. The processing path now runs inside the native Swift app end to end.

- Local-first by default, with on-device transcription and a local LM Studio endpoint configured out of the box
- Draft, judge, and revise passes for meeting notes that read like notes instead of raw transcripts
- Native Swift app flow built around clean Obsidian markdown export

## Why VoiceRaft

- **Local-first workflow.** Meeting audio stays on your Mac, transcription uses Apple's Speech framework, and the default LM Studio base URL points at `http://127.0.0.1:1234/v1`.
- **Better note quality.** VoiceRaft drafts notes, evaluates them, and revises when needed before saving the final markdown.
- **Obsidian-native output.** Notes keep stable frontmatter and structured sections for Summary, Decisions, Action Items, Open Questions / Risks, and Follow-Up.

## How It Works

1. Start a `Room` or `Online` session from the menu bar and give the meeting a title.
2. VoiceRaft records audio and transcribes the finished recording locally after you stop.
3. The native processor drafts notes with LM Studio, judges the result, and revises up to two times when the note needs another pass.
4. Final markdown is written into the Obsidian vault path from config. If the vault write fails, VoiceRaft saves a pending export locally so the note is not lost.

## What You Need

- macOS with microphone access and speech recognition permission enabled for the app
- LM Studio running locally, or another OpenAI-compatible endpoint configured in settings
- An Obsidian vault path provided in config via `AppSettings.obsidianVaultPath`
- For online meetings, the correct helper input device selected in settings if you use loopback or multi-output audio routing

## Quick Start

```bash
xcodebuild -project voiceraft.xcodeproj -scheme voiceraft -configuration Debug CODE_SIGNING_ALLOWED=NO build
open voiceraft.xcodeproj
```

1. Start LM Studio and load the model you want VoiceRaft to use.
2. Run the `voiceraft` scheme from Xcode.
3. On first launch, grant microphone and speech recognition access.
4. Open VoiceRaft Settings and set your Obsidian vault path, LM Studio URL and model, and optional online meeting input device. The vault location is not auto-discovered; it is provided through config and stored as `obsidianVaultPath`.
5. Use the menu bar icon to start and stop meeting capture.

## Architecture

- `voiceraft/` contains the shipping macOS app: AppKit menu bar shell, SwiftUI settings window, recording services, export handling, and the main session coordinator.
- `voiceraft/NativeMeetingProcessor.swift` runs transcription plus the draft, judge, and revise loop directly in Swift.
- `Packages/VoiceRaftCore/` is an in-repo Swift package scaffold for moving more workflow logic under `swift test` over time.

## Development

The primary verified build path is the app target:

```bash
xcodebuild -project voiceraft.xcodeproj -scheme voiceraft -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

If you are iterating on the extraction scaffold under `Packages/VoiceRaftCore`, start here:

```bash
swift test --package-path Packages/VoiceRaftCore
```

Key places to start:

- `voiceraft/SessionCoordinator.swift` for the capture -> process -> export flow
- `voiceraft/NativeMeetingProcessor.swift` for transcription and LM Studio orchestration
- `voiceraft/SettingsUI.swift` and `voiceraft/AppSettings.swift` for runtime configuration

Runtime config lives in `UserDefaults` under `VoiceRaft.AppSettings`. The Obsidian location comes from `obsidianVaultPath`, which the settings window writes explicitly.

## Status

VoiceRaft is currently a Swift-native macOS app with the live workflow in `voiceraft/` and an extraction path taking shape in `Packages/VoiceRaftCore/`. The repository recently dropped the Python sidecar, so the architecture is now consolidating around the native app path rather than a mixed-runtime stack. Today, the app target is the primary verified shipping path while the package scaffold continues to mature.
