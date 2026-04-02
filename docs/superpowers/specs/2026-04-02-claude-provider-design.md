# Claude Provider Design

## Summary

VoiceRaft currently supports only LM Studio for note drafting, judging, and revision. We want to add Claude as a first-class provider that uses a direct Anthropic integration, stores the API key in macOS Keychain, fetches available Claude models at runtime, and lets the user switch between `LM Studio` and `Claude` from the app settings UI.

## Goals

- Add a provider switch between `LM Studio` and `Claude`
- Support direct Anthropic API usage with a user-provided API key
- Store the Claude API key in macOS Keychain rather than `UserDefaults`
- Fetch available Claude models from Anthropic at runtime
- Keep LM Studio working without regression
- Document the new provider flow and Keychain behavior in the README

## Non-Goals

- General multi-provider plugin architecture
- Streaming model responses
- Claude-specific prompt tuning beyond parity with the existing LM Studio prompts
- Secure sync/export of secrets across machines

## Current State

- `AppSettings` stores LM Studio settings, Obsidian path, and online input device in `UserDefaults`
- `SettingsView` exposes LM Studio fields directly with no provider abstraction
- `NativeMeetingProcessor` always constructs `LMStudioMeetingClient`
- There is no secret storage abstraction and no Anthropic integration

## Proposed Architecture

### Provider Selection

Add a `NotesProvider` enum to app settings with two cases:

- `lmStudio`
- `claude`

`AppSettings` will continue to store non-secret provider configuration in `UserDefaults`.

Stored values:

- Shared:
  - `obsidianVaultPath`
  - `onlineInputDeviceID`
  - `notesProvider`
- LM Studio:
  - `lmStudioBaseURL`
  - `lmStudioModel`
- Claude:
  - `claudeModel`

The Claude API key will not be stored in `AppSettings`.

### Secret Storage

Introduce a `KeychainSecretStore` abstraction for provider secrets.

Responsibilities:

- Save Claude API key
- Load Claude API key
- Delete Claude API key
- Return clear error states for missing keychain items or save failures

The initial implementation will store a single secret scoped to VoiceRaft’s bundle identifier and a service/account pair dedicated to Anthropic.

### Provider Clients

Introduce a small provider boundary for note generation. The app should no longer directly assume LM Studio.

Suggested shape:

- `MeetingNotesClient`
  - `draft(transcript:request:)`
  - `judge(transcript:draft:)`
  - `revise(draft:feedback:request:)`
- `LMStudioMeetingClient`
- `ClaudeMeetingClient`

`NativeMeetingProcessor.makeClient(settings:)` will switch on `notesProvider` and construct the appropriate implementation.

### Claude Integration

`ClaudeMeetingClient` will use Anthropic’s Messages API directly.

Requirements:

- Base endpoint: `https://api.anthropic.com`
- Headers:
  - `x-api-key`
  - `anthropic-version`
  - `content-type: application/json`
- Request path:
  - `POST /v1/messages`

The existing draft, judge, and revise prompts will be preserved as much as possible so the provider swap changes transport, not workflow intent.

The Claude client will ask for structured JSON output and decode the result into the same local Swift types currently used by the LM Studio path.

### Claude Model Discovery

Introduce `AnthropicModelsService`.

Responsibilities:

- Fetch available Claude models using the stored Anthropic API key
- Decode the response from `GET /v1/models`
- Filter or sort models for settings display
- Surface runtime fetch errors back to the UI

The settings UI should fetch models on demand when:

- Claude is selected
- a valid API key is available
- the user taps a refresh action

To keep the UI responsive, the model list should have explicit loading, loaded, and failed states.

## Settings UI Changes

### Provider Switch

Add a top-level control in settings for the notes provider.

Recommended UI:

- Picker or segmented control labeled `Notes Provider`
- Values:
  - `LM Studio`
  - `Claude`

### LM Studio Section

Shown when `LM Studio` is selected:

- `LM Studio base URL`
- `LM Studio model`

This stays close to the current layout.

### Claude Section

Shown when `Claude` is selected:

- Secure API key input
- Save or update key action
- Optional clear key action
- Claude model picker
- Refresh models button
- Loading state text while models are fetched
- Inline error text if model fetch fails

If no API key is present:

- disable the model picker
- show a prompt to save the key first

If a previously saved model is no longer available:

- preserve the saved value
- mark that selection as unavailable
- prompt the user to choose a currently available model

## Processing Flow

1. Capture audio
2. Transcribe with Apple Speech
3. Build workflow request payload
4. Resolve notes provider from settings
5. Construct provider client
6. Run draft, judge, revise workflow
7. Render markdown
8. Save to Obsidian or pending export

Provider-specific failure should happen only in step 5 or later.

## Error Handling

### Claude Configuration Errors

Add user-facing failures for:

- missing Claude API key
- failed Claude key save/load
- invalid Claude model selection
- model fetch failure
- Anthropic request failure
- Anthropic timeout
- malformed Anthropic response

### UI Behavior

- Missing Claude API key should be caught before attempting note generation
- Model fetch errors should not crash settings; they should display inline and allow retry
- Processing failures should continue to use the existing alert and notification flow

## README Updates

Update README to document:

- provider choice between LM Studio and Claude
- direct Anthropic integration
- Claude API key storage in macOS Keychain
- runtime model fetching from Anthropic
- what the user needs to configure for each provider

## Testing Plan

### Unit Tests

- `AppSettings` round-trip for `notesProvider` and `claudeModel`
- keychain store read/write/delete behavior behind a mockable protocol
- Anthropic model list request and decoding
- Claude request building:
  - endpoint
  - headers
  - model
  - prompt payload
- Claude response decoding into draft and judge types
- typed timeout and malformed response errors

### UI/Behavior Tests

- provider switch changes visible settings section
- Claude model picker is disabled without a saved API key
- model list loads after saving a valid API key
- model fetch error is surfaced inline

### Regression Coverage

- LM Studio path still works with existing settings
- README still matches runtime configuration

## Rollout Notes

- Existing users should default to `LM Studio` after upgrading
- Existing LM Studio settings should remain intact
- Claude-specific settings should be additive and optional
- Keychain lookup must fail safely when no Claude key has been saved yet
