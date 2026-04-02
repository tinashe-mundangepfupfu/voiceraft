# Swift Native Meeting Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Python sidecar with an in-process Swift workflow that handles transcription, LM Studio drafting/judging/revision, markdown rendering, and app integration without changing the menu bar flow.

**Architecture:** Extract the workflow logic into a local Swift package so it can be tested with `swift test` before the macOS app target depends on it. Keep the app shell responsible for recording, notifications, export, and menu state while the package owns transcription, prompting, markdown, and workflow retries.

**Tech Stack:** Swift 5, Swift Package Manager, XCTest or Swift Testing via `swift test`, Speech framework, AVFAudio, Foundation networking, Xcode project local package integration

---

### Task 1: Create a testable workflow package boundary

**Files:**
- Create: `Packages/VoiceRaftCore/Package.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/MeetingWorkflowEngineTests.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/MarkdownRendererTests.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/LMStudioClientTests.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/TestDoubles.swift`

- [ ] **Step 1: Write the failing workflow tests**

Create tests that describe:
- immediate judge approval returns `final`
- rejected draft retries and eventually returns `final`
- rejected draft after max retries returns `needs-review`
- markdown frontmatter and sections match the existing Python renderer
- LM Studio client encodes requests and decodes structured JSON responses

- [ ] **Step 2: Run the package tests to verify they fail**

Run: `swift test --package-path Packages/VoiceRaftCore`
Expected: FAIL because the package target types do not exist yet.

- [ ] **Step 3: Commit the failing tests scaffold**

```bash
git add Packages/VoiceRaftCore
git commit -m "test: scaffold native workflow package tests"
```

### Task 2: Implement workflow models, renderer, and retry engine

**Files:**
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/WorkflowModels.swift`
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/MarkdownRenderer.swift`
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/MeetingWorkflowEngine.swift`
- Modify: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/MeetingWorkflowEngineTests.swift`
- Modify: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/MarkdownRendererTests.swift`

- [ ] **Step 1: Add the minimal production models and renderer**

Implement Swift equivalents of:
- `ActionItem`
- `MeetingNoteSections`
- `Frontmatter`
- `DraftNote`
- `JudgeFeedback`
- `JudgeDecision`
- `MeetingWorkflowRequest`
- `MeetingWorkflowResult`

Add a markdown renderer that preserves the current frontmatter keys and section headings.

- [ ] **Step 2: Implement the retry-based workflow engine**

Implement a native `MeetingWorkflowEngine` that:
- transcribes audio
- drafts notes
- judges notes
- revises while retries remain
- returns `final` or `needs-review`

- [ ] **Step 3: Run focused tests until green**

Run: `swift test --package-path Packages/VoiceRaftCore --filter MeetingWorkflowEngineTests`
Expected: PASS

Run: `swift test --package-path Packages/VoiceRaftCore --filter MarkdownRendererTests`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Packages/VoiceRaftCore
git commit -m "feat: add native workflow engine and markdown renderer"
```

### Task 3: Implement native transcription and LM Studio integration

**Files:**
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/TranscriptService.swift`
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/LMStudioClient.swift`
- Modify: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/LMStudioClientTests.swift`
- Modify: `Packages/VoiceRaftCore/Package.swift`

- [ ] **Step 1: Add failing LM Studio and transcription-facing tests**

Describe behaviors for:
- chat-completions request encoding
- structured JSON decoding for draft and judge outputs
- malformed output surfaces a typed error

- [ ] **Step 2: Implement minimal client and transcription service**

Implement:
- `AppleSpeechTranscriptService` using the Speech framework on macOS 26+
- `LMStudioClient` with injected transport for tests
- prompt builders for draft, judge, and revise
- JSON extraction and decoding helpers

- [ ] **Step 3: Re-run the package suite**

Run: `swift test --package-path Packages/VoiceRaftCore`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Packages/VoiceRaftCore
git commit -m "feat: add native speech transcription and lm studio client"
```

### Task 4: Wire the app target to the native package

**Files:**
- Modify: `voiceraft.xcodeproj/project.pbxproj`
- Modify: `voiceraft/SessionCoordinator.swift`
- Modify: `voiceraft/AppSettings.swift`
- Modify: `voiceraft/SettingsUI.swift`
- Modify: `voiceraft/VoiceRaftError.swift`
- Modify: `voiceraft/MeetingModels.swift`
- Delete: `voiceraft/SidecarManager.swift`

- [ ] **Step 1: Add the local package to the app target**

Add `Packages/VoiceRaftCore` as a local package dependency for the `voiceraft` target.

- [ ] **Step 2: Replace sidecar invocation with native engine execution**

Update `SessionCoordinator` to build a `MeetingWorkflowRequest`, call the native engine, and keep the current export and pending-save behavior.

- [ ] **Step 3: Remove sidecar-only settings and errors**

Remove:
- sidecar host
- sidecar port
- sidecar executable error states
- sidecar launch/request error strings

Keep:
- project root if still needed for local assets, otherwise remove it too
- LM Studio base URL
- LM Studio model

- [ ] **Step 4: Run an app build**

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add voiceraft.xcodeproj voiceraft
git commit -m "feat: switch app processing to native swift workflow"
```

### Task 5: Remove Python sidecar assets once Swift path is proven

**Files:**
- Delete: `sidecar/`
- Modify: `pyproject.toml`
- Modify: `.gitignore` if needed
- Modify: `docs/superpowers/specs/2026-03-29-native-langgraph-swift-design.md` if rollout notes need updating

- [ ] **Step 1: Verify no Swift code still references the sidecar**

Run: `rg -n "sidecar|Sidecar" voiceraft Packages/VoiceRaftCore`
Expected: only historical documentation or intentionally retained migration notes remain.

- [ ] **Step 2: Remove Python runtime artifacts**

Delete the sidecar package and related packaging config only after the app and package checks are green.

- [ ] **Step 3: Run final verification**

Run: `swift test --package-path Packages/VoiceRaftCore`
Expected: PASS

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove python sidecar"
```
