# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceRaft is a macOS menu-bar app that captures meeting audio, transcribes it locally, generates structured meeting notes via LM Studio, and exports them to an Obsidian vault. The processing flow now runs inside the native Swift app.

## Architecture

**Swift app** (`voiceraft/`): macOS menu-bar app using AppKit with a small SwiftUI settings window. Handles audio capture, speech recognition transcription, LM Studio note generation, judge/revise retries, notifications, and Obsidian vault writing. Entry point is `main.swift` which creates an NSApplication with `.accessory` activation policy. `VoiceRaftAppDelegate` owns the menu bar; `SessionCoordinator` orchestrates the recording→processing→export flow.

**Native processing** (`voiceraft/NativeMeetingProcessor.swift`): Runs the AI pipeline in-process. The flow is: transcribe recorded audio with Apple's Speech framework → draft notes via LM Studio → judge quality → optionally revise up to 2 rounds → render markdown for Obsidian export.

**Workflow package scaffold** (`Packages/VoiceRaftCore/`): An in-repo Swift package for moving workflow logic under `swift test` over time. It is currently for package-level extraction and testing work, while the shipping app path is the native Swift processor in `voiceraft/`.

## Build & Run

### Swift app
```bash
xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build
```

### Swift package checks
```bash
swift test --package-path Packages/VoiceRaftCore
```

## Key Configuration

Settings are stored in UserDefaults under `VoiceRaft.AppSettings`. Important defaults:
- LM Studio: `http://127.0.0.1:1234/v1`, model `qwen3-8b-deepseek-v3.2-speciale-distill`

## Conventions

- Swift uses `@MainActor` isolation for UI-touching classes and `actor` for the meeting processor.
- The app should preserve its current guarantees: no silent data loss, delete raw audio only after a successful Obsidian save, and save a pending export when vault writing fails.
- When changing note generation, keep the markdown frontmatter keys and section headings stable so existing Obsidian organization still works.
