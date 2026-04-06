# Claude Provider Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a runtime-selectable Claude provider alongside LM Studio, with Anthropic API-key storage in macOS Keychain, runtime Claude model discovery, and README documentation.

**Architecture:** Reuse `VoiceRaftCore.MeetingNotesModeling` as the provider boundary. Keep Anthropic request/response logic and tests in `Packages/VoiceRaftCore`, while the app target owns provider selection, Keychain storage, runtime settings, and the provider-aware settings UI.

**Tech Stack:** Swift 6.1, Swift Package Manager, AppKit, SwiftUI, URLSession, macOS Security/Keychain Services, xcodebuild, swift test

---

## File Map

- `Packages/VoiceRaftCore/Sources/VoiceRaftCore/WorkflowModels.swift`
  Adds Anthropic-specific typed errors if needed by the package client.
- `Packages/VoiceRaftCore/Sources/VoiceRaftCore/LMStudioClient.swift`
  Existing LM Studio provider implementation; keep behavior intact.
- `Packages/VoiceRaftCore/Sources/VoiceRaftCore/ClaudeClient.swift`
  New Anthropic Messages API implementation of `MeetingNotesModeling`.
- `Packages/VoiceRaftCore/Sources/VoiceRaftCore/AnthropicModelsService.swift`
  New paginated model-list fetcher for `claude-*` model IDs.
- `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/ClaudeClientTests.swift`
  New request/response tests for Claude drafting, judging, revising, and failure modes.
- `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/AnthropicModelsServiceTests.swift`
  New tests for paginated model discovery and filtering/sorting.
- `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/TestDoubles.swift`
  Shared fixtures for package-level provider tests.
- `voiceraft/AppSettings.swift`
  Add provider-aware settings model with backward-compatible decoding.
- `voiceraft/KeychainSecretStore.swift`
  New app-side Keychain wrapper for Claude API key storage.
- `voiceraft/ClaudeSettingsModel.swift`
  New app-side observable helper for Claude key/model loading state.
- `voiceraft/SettingsUI.swift`
  Add provider picker and provider-specific settings sections.
- `voiceraft/NativeMeetingProcessor.swift`
  Replace hard-coded LM Studio client construction with provider selection.
- `voiceraft/VoiceRaftError.swift`
  Add user-facing Claude configuration/network/model errors.
- `tools/app_settings_provider_check.swift`
  New source-level regression check for backward-compatible provider fields in `AppSettings`.
- `tools/claude_settings_ui_check.swift`
  New source-level regression check for provider switch and Claude settings controls.
- `tools/native_provider_selection_check.swift`
  New source-level regression check for provider-aware client selection and Claude model validation.
- `README.md`
  Document LM Studio vs Claude setup, Keychain storage, and runtime Claude model fetching.

### Task 1: Add Provider-Aware Settings With Backward-Compatible Decode

**Files:**
- Modify: `voiceraft/AppSettings.swift`
- Create: `tools/app_settings_provider_check.swift`

- [ ] **Step 1: Write the failing source-level regression check**

```swift
try assert(source.contains("enum NotesProvider"))
try assert(source.contains("decodeIfPresent"))
try assert(source.contains(".lmStudio"))
try assert(source.contains("claudeModel"))
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `xcrun swiftc -parse-as-library tools/app_settings_provider_check.swift -o .build/tool-checks/app_settings_provider_check && .build/tool-checks/app_settings_provider_check`
Expected: FAIL because `AppSettings` does not yet define provider-aware fields or a backward-compatible decode path.

- [ ] **Step 3: Implement minimal provider-aware settings**

Add:

- `enum NotesProvider: String, Codable, Equatable`
- `notesProvider` and `claudeModel` to `AppSettings`
- custom `init(from:)` that defaults:
  - `notesProvider` to `.lmStudio`
  - `claudeModel` to `""`
- preserve existing decoded LM Studio settings instead of falling back to `.default()`

- [ ] **Step 4: Re-run the source check**

Run: `xcrun swiftc -parse-as-library tools/app_settings_provider_check.swift -o .build/tool-checks/app_settings_provider_check && .build/tool-checks/app_settings_provider_check`
Expected: PASS

- [ ] **Step 5: Verify the app still builds with the new settings model**

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add voiceraft/AppSettings.swift tools/app_settings_provider_check.swift
git commit -m "feat: add provider-aware app settings"
```

### Task 2: Add Anthropic Provider And Model Discovery In VoiceRaftCore

**Files:**
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/ClaudeClient.swift`
- Create: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/AnthropicModelsService.swift`
- Modify: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/WorkflowModels.swift`
- Modify: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/TestDoubles.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/ClaudeClientTests.swift`
- Create: `Packages/VoiceRaftCore/Tests/VoiceRaftCoreTests/AnthropicModelsServiceTests.swift`

- [ ] **Step 1: Write the failing Claude provider tests**

Include tests for:

```swift
func testDraftBuildsAnthropicMessagesRequest() async throws
func testJudgeBuildsAnthropicMessagesRequest() async throws
func testDraftMapsTimeoutToTypedError() async
func testDraftRejectsMissingStructuredJSON() async
```

Use assertions for:

- `POST https://api.anthropic.com/v1/messages`
- `x-api-key`
- `anthropic-version: 2023-06-01`
- `system`
- `messages`
- `output_config.format.type == "json_schema"`

- [ ] **Step 2: Write the failing Anthropic model discovery tests**

Include tests for:

```swift
func testListModelsFollowsPaginationAndSortsClaudeIDs() async throws
func testListModelsFiltersToClaudePrefixedIDs() async throws
func testListModelsMapsTimeoutToTypedError() async
```

- [ ] **Step 3: Run the package suite to verify failure**

Run: `xcrun swift test --package-path Packages/VoiceRaftCore`
Expected: FAIL in the new Claude client/model service tests because the implementations do not exist yet.

- [ ] **Step 4: Implement the minimal Claude client**

Implement `ClaudeClient` as `MeetingNotesModeling` using:

- `POST /v1/messages`
- `system`
- single `user` message
- `output_config.format`
- typed request/response decoding
- timeout handling
- typed malformed-response handling

- [ ] **Step 5: Implement the minimal paginated model service**

Implement `AnthropicModelsService` using:

- `GET /v1/models`
- cursor pagination until no more pages
- filter to `claude-*`
- alphabetical sort by model ID

- [ ] **Step 6: Run the package suite to verify it passes**

Run: `xcrun swift test --package-path Packages/VoiceRaftCore`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Packages/VoiceRaftCore
git commit -m "feat: add Anthropic Claude provider"
```

### Task 3: Add Keychain Storage And Claude Settings State In The App

**Files:**
- Create: `voiceraft/KeychainSecretStore.swift`
- Create: `voiceraft/ClaudeSettingsModel.swift`
- Modify: `voiceraft/VoiceRaftError.swift`
- Modify: `voiceraft.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing app-side settings/UI source check**

Create `tools/claude_settings_ui_check.swift` with assertions such as:

```swift
try assert(settingsSource.contains("Notes Provider"))
try assert(settingsSource.contains("Claude"))
try assert(settingsSource.contains("SecureField"))
try assert(settingsSource.contains("Refresh Models"))
try assert(settingsSource.contains("Save API Key"))
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `xcrun swiftc -parse-as-library tools/claude_settings_ui_check.swift -o .build/tool-checks/claude_settings_ui_check && .build/tool-checks/claude_settings_ui_check`
Expected: FAIL because the app has no Claude settings controls yet.

- [ ] **Step 3: Implement the Keychain wrapper and app-side Claude state model**

Add:

- `KeychainSecretStore` with save/load/delete for the Anthropic key
- `ClaudeSettingsModel` to coordinate:
  - saved-key status
  - model list loading
  - model list errors
  - preserving an unavailable saved `claudeModel` in UI state until the user reselects
  - auto-fetch after key save

Add provider-specific `VoiceRaftError` cases for:

- missing Claude API key
- model fetch failure
- invalid Claude model

- [ ] **Step 4: Add new files to the Xcode project**

Update `voiceraft.xcodeproj/project.pbxproj` so the app target builds:

- `KeychainSecretStore.swift`
- `ClaudeSettingsModel.swift`

- [ ] **Step 5: Run an app build to verify the new support code compiles**

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add voiceraft/KeychainSecretStore.swift voiceraft/ClaudeSettingsModel.swift voiceraft/VoiceRaftError.swift voiceraft.xcodeproj/project.pbxproj tools/claude_settings_ui_check.swift
git commit -m "feat: add Claude keychain support"
```

### Task 4: Add Provider Switching And Claude Controls To Settings UI

**Files:**
- Modify: `voiceraft/SettingsUI.swift`
- Modify: `voiceraft/AppSettings.swift`
- Modify: `voiceraft/VoiceRaftAppDelegate.swift` (only if needed for settings model ownership)

- [ ] **Step 1: Write the failing UI behavior assertions in the source check**

Extend `tools/claude_settings_ui_check.swift` to verify:

```swift
try assert(settingsSource.contains("binding(\\.notesProvider)"))
try assert(settingsSource.contains("binding(\\.claudeModel)"))
try assert(settingsSource.contains("Picker(\"Claude model\""))
try assert(settingsSource.contains("provider-specific"))
```

- [ ] **Step 2: Run the source check to verify failure**

Run: `xcrun swiftc -parse-as-library tools/claude_settings_ui_check.swift -o .build/tool-checks/claude_settings_ui_check && .build/tool-checks/claude_settings_ui_check`
Expected: FAIL because the settings UI still only exposes LM Studio fields.

- [ ] **Step 3: Implement minimal provider-aware settings UI**

Add:

- provider picker labeled `Notes Provider`
- conditional LM Studio section
- conditional Claude section with:
  - secure key field
  - save/update key button
  - clear key action
  - model picker
  - refresh button
  - loading/error/empty states
  - unavailable selected-model messaging when the stored `claudeModel` is not in the fetched Anthropic list

- [ ] **Step 4: Wire first-time Claude model auto-selection**

When:

- Claude key saves successfully
- no `claudeModel` is stored
- fetched list is non-empty

Then:

- pick the first sorted model ID
- persist it into `AppSettings`

- [ ] **Step 5: Preserve unavailable saved Claude models in the picker**

When:

- `AppSettings.claudeModel` is non-empty
- the refreshed Anthropic model list does not include it

Then:

- keep the stored `claudeModel` value unchanged
- render it as an unavailable option or inline warning in settings
- leave Claude note generation blocked until the user selects a currently available model

- [ ] **Step 6: Re-run the settings source check**

Run: `xcrun swiftc -parse-as-library tools/claude_settings_ui_check.swift -o .build/tool-checks/claude_settings_ui_check && .build/tool-checks/claude_settings_ui_check`
Expected: PASS

- [ ] **Step 7: Re-run the app build**

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add voiceraft/SettingsUI.swift voiceraft/AppSettings.swift voiceraft/VoiceRaftAppDelegate.swift tools/claude_settings_ui_check.swift
git commit -m "feat: add provider switch to settings"
```

### Task 5: Wire Native Processing To The Selected Provider

**Files:**
- Modify: `voiceraft/NativeMeetingProcessor.swift`
- Modify: `voiceraft/VoiceRaftError.swift`
- Modify: `Packages/VoiceRaftCore/Sources/VoiceRaftCore/VoiceRaftCore.swift` (only if public exports need to be surfaced)

- [ ] **Step 1: Write a focused failing integration-oriented package/app test target substitute**

Add a minimal source-level guard, either in an existing tool check or a new one, asserting:

```swift
try assert(processorSource.contains("switch settings.notesProvider"))
try assert(processorSource.contains("ClaudeClient"))
try assert(processorSource.contains("LMStudioClient") || processorSource.contains("LMStudioMeetingClient"))
```

- [ ] **Step 2: Run the guard to verify failure**

Run: `xcrun swiftc -parse-as-library tools/native_provider_selection_check.swift -o .build/tool-checks/native_provider_selection_check && .build/tool-checks/native_provider_selection_check`
Expected: FAIL because `NativeMeetingProcessor` is still hard-coded to LM Studio.

- [ ] **Step 3: Replace hard-coded LM Studio selection with provider switching**

Implement:

- LM Studio path using existing settings
- Claude path requiring:
  - saved Claude API key
  - selected Claude model that is non-empty and still present in the current Anthropic model list
- mapping package errors into `VoiceRaftError`

- [ ] **Step 4: Remove duplicate provider logic where possible**

If practical in the minimal change set:

- keep prompt orchestration in one place
- avoid introducing a second provider abstraction in the app target

- [ ] **Step 5: Run the provider-selection guard**

Run: `xcrun swiftc -parse-as-library tools/native_provider_selection_check.swift -o .build/tool-checks/native_provider_selection_check && .build/tool-checks/native_provider_selection_check`
Expected: PASS

- [ ] **Step 6: Run the package suite and app build**

Run: `xcrun swift test --package-path Packages/VoiceRaftCore`
Expected: PASS

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add voiceraft/NativeMeetingProcessor.swift voiceraft/VoiceRaftError.swift tools/native_provider_selection_check.swift Packages/VoiceRaftCore/Sources/VoiceRaftCore/VoiceRaftCore.swift
git commit -m "feat: wire runtime provider selection"
```

### Task 6: Update README And Run Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-04-02-claude-provider-design.md` (only if implementation-driven clarifications are needed)

- [ ] **Step 1: Update README for both providers**

Add documentation for:

- selecting `LM Studio` vs `Claude`
- Claude API key storage in macOS Keychain
- runtime Claude model fetching
- initial Claude setup flow
- requirement to choose a currently available Claude model

- [ ] **Step 2: Verify README mentions the real runtime config**

Check that README matches:

- `UserDefaults` for non-secret settings
- Keychain for Claude API key
- provider selection in settings

- [ ] **Step 3: Run all final verification commands**

Run: `xcrun swift test --package-path Packages/VoiceRaftCore`
Expected: PASS

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcrun swiftc -parse-as-library tools/app_settings_provider_check.swift -o .build/tool-checks/app_settings_provider_check && .build/tool-checks/app_settings_provider_check`
Expected: PASS

Run: `xcrun swiftc -parse-as-library tools/claude_settings_ui_check.swift -o .build/tool-checks/claude_settings_ui_check && .build/tool-checks/claude_settings_ui_check`
Expected: PASS

Run: `xcrun swiftc -parse-as-library tools/native_provider_selection_check.swift -o .build/tool-checks/native_provider_selection_check && .build/tool-checks/native_provider_selection_check`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/2026-04-02-claude-provider-design.md
git commit -m "docs: add Claude provider setup"
```
