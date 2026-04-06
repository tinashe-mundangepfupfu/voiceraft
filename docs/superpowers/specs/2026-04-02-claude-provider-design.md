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

Backward compatibility requirement:

- existing saved `AppSettings` records must continue decoding without data loss
- add a custom decode path for new settings fields so older saved payloads default `notesProvider` to `lmStudio` and `claudeModel` to an empty string
- preserve existing LM Studio values in place rather than replacing the whole settings object with `.default()`

### Secret Storage

Introduce a `KeychainSecretStore` abstraction for provider secrets.

Responsibilities:

- Save Claude API key
- Load Claude API key
- Delete Claude API key
- Return clear error states for missing keychain items or save failures

The initial implementation will store a single secret scoped to VoiceRaft’s bundle identifier and a service/account pair dedicated to Anthropic.

### Provider Clients

Reuse the existing `VoiceRaftCore.MeetingNotesModeling` boundary for note generation rather than introducing a second provider protocol in the app target.

Ownership:

- provider client implementations should live in `Packages/VoiceRaftCore` where possible so request building, decoding, and tests stay in one place
- the app target should remain responsible for runtime settings resolution, keychain wiring, and selecting the active provider at runtime

Concrete implementations:

- `LMStudioClient` in `VoiceRaftCore` remains the LM Studio implementation of `MeetingNotesModeling`
- add `ClaudeClient` in `VoiceRaftCore` as the Anthropic implementation of `MeetingNotesModeling`

`NativeMeetingProcessor.makeClient(settings:)` will switch on `notesProvider` and construct the appropriate `MeetingNotesModeling` implementation.

### Claude Integration

`ClaudeMeetingClient` will use Anthropic’s Messages API directly.

Requirements:

- Base endpoint: `https://api.anthropic.com`
- Headers:
  - `x-api-key`
  - `anthropic-version: 2023-06-01`
  - `content-type: application/json`
- Request path:
  - `POST /v1/messages`

The existing draft, judge, and revise prompts will be preserved as much as possible so the provider swap changes transport, not workflow intent.

Request shape:

- use the top-level `system` field for the system prompt
- send a single `user` message containing the task-specific prompt payload
- include `model`
- include `max_tokens`
- include `output_config.format` with `type: "json_schema"` and a schema matching the expected draft or judge payload

Anthropic contract note:

- use the current Claude API structured-output path documented by Anthropic for direct API calls
- do not rely on deprecated `output_format`
- do not require a beta header for structured outputs in this feature
- if Anthropic rejects structured output for a selected model, surface a typed Claude-provider error telling the user to pick a supported Claude model

Response handling:

- read validated JSON text from the first text block in `response.content`
- decode that JSON into the same local Swift types currently used by the LM Studio path
- treat missing text content, invalid JSON, or schema mismatch as typed Claude response failures

### Claude Model Discovery

Introduce `AnthropicModelsService`.

Responsibilities:

- Fetch available Claude models using the stored Anthropic API key
- Decode the response from `GET /v1/models`
- Filter or sort models for settings display
- Surface runtime fetch errors back to the UI
- Follow pagination until `has_more` is false so the picker includes the full available Claude model set

Display rules:

- sort models alphabetically by model ID for deterministic picker order
- show the Anthropic model ID directly in the picker
- include every model returned by Anthropic whose model ID starts with `claude-`

The settings UI should fetch models automatically when:

- Claude is selected
- a valid API key has just been saved

The settings UI should also allow a manual refresh action after that initial fetch.

Pagination rule:

- follow Anthropic model-list pagination until the API indicates there are no more pages

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

If a Claude API key is saved successfully:

- immediately fetch the available Claude models
- populate the picker from the fetched results
- if no `claudeModel` is already stored and the fetch returns at least one model, auto-select the first model in the sorted list and persist it

If the Claude API key is cleared:

- keep the stored `claudeModel` value so the user’s previous Claude model preference is preserved for a future re-enable flow
- disable Claude model use until a new valid Claude API key is saved

If a previously saved model is no longer available:

- preserve the saved value
- mark that selection as unavailable
- prompt the user to choose a currently available model
- block Claude note generation until the user selects a currently available Claude model

If no `claude-` models are returned:

- disable the Claude model picker
- show an inline empty-state message
- block Claude note generation until a refresh returns at least one supported Claude model

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

Reference docs for implementation:

- Anthropic versioning: https://platform.claude.com/docs/en/api/versioning
- Anthropic Messages API: https://docs.anthropic.com/en/api/messages
- Anthropic structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- Anthropic models list: https://docs.anthropic.com/en/api/models-list

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
- model list loads automatically after saving a valid API key
- first-time Claude setup auto-selects the first available model when no Claude model has been stored yet
- model fetch error is surfaced inline

### Regression Coverage

- LM Studio path still works with existing settings
- README still matches runtime configuration

## Rollout Notes

- Existing users should default to `LM Studio` after upgrading
- Existing LM Studio settings should remain intact
- Claude-specific settings should be additive and optional
- Keychain lookup must fail safely when no Claude key has been saved yet
- Settings migration should happen through backward-compatible decoding rather than a one-time destructive reset
