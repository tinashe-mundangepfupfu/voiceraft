# VoiceRaft Native LangGraph-Swift Refactor Design

## Summary

Refactor VoiceRaft from a mixed Swift plus Python architecture into a fully native macOS app that keeps audio capture, notifications, and Obsidian export in Swift while replacing the Python sidecar with a native Swift workflow engine built on `LangGraph-Swift`.

The user-facing behavior should stay the same:

- Manual menu-bar start and stop flow for `Room` and `Online` meetings.
- Batch processing after the meeting ends.
- Professional Obsidian markdown output with structured sections and frontmatter.
- `LM Studio` remains the LLM backend.
- Local transcription remains part of the pipeline.
- Raw audio is deleted only after a successful Obsidian save.

## Goals

- Remove the Python sidecar and run the full workflow inside the macOS app process.
- Use `LangGraph-Swift` to express orchestration, retries, and judge-driven revision logic.
- Preserve the current note structure, quality bar, and failure behavior.
- Keep `LM Studio` as the OpenAI-compatible inference backend for drafting, judging, and revising notes.
- Keep the architecture modular so transcription and model backends can evolve later without rewriting app-level flow.

## Non-Goals

- Replacing `LM Studio` with Apple Foundation Models in this change.
- Redesigning the menu-bar UX.
- Adding live transcription or live note drafting.
- Adding calendar integrations, multilingual-first support, or cloud sync.
- Broad cleanup unrelated to the Python-to-Swift workflow migration.

## Current State

VoiceRaft currently splits responsibilities across two runtimes:

- The Swift app handles recording, session state, notifications, pending export storage, and Obsidian file writing.
- The Python sidecar handles transcription, LangGraph orchestration, draft generation, judge evaluation, revision retries, and API responses back to Swift.

The architectural seam today is [voiceraft/SidecarManager.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/SidecarManager.swift), which launches the sidecar, health-checks it, and sends a `/process` request.

## Proposed Architecture

Move the workflow into native Swift and keep the app as a single macOS process:

`menu bar app -> audio capture -> transcript service -> LangGraph-Swift workflow -> LM Studio client -> markdown renderer -> Obsidian vault writer`

### Layers

1. App shell
   - Existing menu-bar controls, settings, notifications, and recording lifecycle remain in Swift.

2. Workflow layer
   - A native `MeetingWorkflowEngine` owns graph execution and returns the same conceptual result the sidecar returned before.

3. AI service layer
   - A `TranscriptService` produces transcript text from a local audio file.
   - An `LMStudioClient` makes direct OpenAI-compatible HTTP requests for drafting, judging, and revising.

4. Output layer
   - A `MarkdownRenderer` produces the final Obsidian markdown payload.
   - Existing export and pending-save helpers continue to own persistence behavior.

## Component Design

### `MeetingWorkflowEngine`

Responsibilities:

- Build and run the `LangGraph-Swift` graph.
- Translate raw workflow state into a final app-facing result.
- Enforce max revision count.
- Return `final` or `needs-review` status with confidence and judge summary.

### `MeetingWorkflowState`

State carried through the graph:

- Request metadata
- Audio file URL
- Transcript text
- Normalized transcript text
- Current structured note draft
- Current judge result
- Revision count
- Final status

This should be the Swift equivalent of the current Python workflow state while staying idiomatic to `LangGraph-Swift`.

### `TranscriptService`

Responsibilities:

- Accept a recorded audio file URL.
- Return English transcript text.
- Hide the underlying local transcription implementation from the rest of the app.

This service should be defined behind a protocol so the workflow can be tested with fixtures and stubs.

### `LMStudioClient`

Responsibilities:

- Call `LM Studio` directly over HTTP using its OpenAI-compatible chat-completions style API.
- Expose typed operations for:
  - `draftNote`
  - `judgeNote`
  - `reviseNote`
- Decode structured responses into Swift models.

This keeps prompting and response parsing inside Swift instead of splitting it across network JSON and Python models.

### `PromptLibrary`

Responsibilities:

- Store system prompts and user prompt templates for draft, judge, and revise stages.
- Keep the rubric explicit:
  - no unsupported claims
  - clear separation between decisions and open questions
  - professional tone
  - explicit uncertainty labeling
  - action items only with explicit or strongly inferable owners

### `MarkdownRenderer`

Responsibilities:

- Convert the structured note model into final Obsidian markdown.
- Preserve current frontmatter shape:
  - `title`
  - `date`
  - `meeting_mode`
  - `language`
  - `status`
  - `tags`
- Preserve current sections:
  - `Summary`
  - `Key Discussion Points`
  - `Decisions`
  - `Action Items`
  - `Open Questions / Risks`
  - `Follow-Up`

## Workflow Graph

The graph remains behaviorally equivalent to the Python version:

`transcribe -> normalize -> draft -> judge`

Then:

- if judge approves: finish as `final`
- if judge rejects and retries remain: `revise -> judge`
- if judge rejects and retries are exhausted: finish as `needs-review`

### Graph Nodes

- `transcribe`
  - Audio file to transcript text
- `normalize`
  - Clean transcript whitespace and formatting for prompt quality
- `draft`
  - Structured note draft from transcript and meeting metadata
- `judge`
  - Quality evaluation against rubric
- `revise`
  - Draft update using judge feedback

### Graph Routing Rules

- Approval ends the graph immediately.
- Rejection with retries remaining routes to `revise`.
- Rejection after max retries ends with `needs-review`.

## Integration Changes

### Keep

- [voiceraft/AudioCaptureService.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/AudioCaptureService.swift)
- [voiceraft/SupportServices.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/SupportServices.swift)
- [voiceraft/MeetingModels.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/MeetingModels.swift)
- Existing menu-bar app delegate and settings UI structure

### Replace

- [voiceraft/SidecarManager.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/SidecarManager.swift)
- Python-side request and response models
- Python-side graph, prompting, and markdown rendering

### Update

- [voiceraft/SessionCoordinator.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/SessionCoordinator.swift)
  - Replace sidecar invocation with in-process workflow execution.
- [voiceraft/AppSettings.swift](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft/AppSettings.swift)
  - Remove sidecar host and port settings once unused.
  - Keep `LM Studio` base URL and model settings.
- [voiceraft.xcodeproj/project.pbxproj](/Users/tmundangepfupfu/source/voiceraft/voiceraft/voiceraft.xcodeproj/project.pbxproj)
  - Add Swift package dependency for `LangGraph-Swift`.
  - Remove Python-sidecar assumptions from the app target.

## Error Handling

The native workflow should preserve the current no-silent-loss behavior.

### Typed Workflow Errors

Examples:

- `transcriptionFailed`
- `lmStudioUnavailable`
- `invalidLMStudioResponse`
- `workflowExecutionFailed`
- `judgeRejectedAfterRetries`

### Required Behaviors

- If transcription fails, the audio file is preserved.
- If `LM Studio` is unavailable or returns an invalid response, the audio file is preserved.
- If the judge still rejects after retries, a `needs-review` markdown note is still generated and saved.
- If Obsidian export fails, the rendered markdown is saved locally for retry and the audio file is preserved.
- Raw audio is deleted only after a confirmed successful vault write.

## Testing Strategy

This migration should be validated as a behavior-preserving refactor.

### Unit Tests

- Workflow node tests for:
  - `draft`
  - `judge`
  - `revise`
  - final status selection
- Markdown rendering tests for frontmatter and section layout
- `LMStudioClient` request/response parsing tests with mocked HTTP responses

### Graph Tests

- Immediate judge pass -> `final`
- Judge fail -> revise -> pass -> `final`
- Judge fail -> revise until retries exhausted -> `needs-review`

### Integration Tests

- Session stop runs native workflow and exports valid markdown to the configured vault path
- Obsidian write failure creates a pending local export
- Failed workflow paths do not delete audio artifacts

### Migration Gate

The Python sidecar and Python tests should only be removed after Swift tests cover the same decision logic and failure paths.

## Risks

- `LangGraph-Swift` is a community package, not an official LangChain Swift SDK, so we should keep its usage narrowly focused on orchestration.
- Native local transcription may require more implementation work than the existing Python wrapper.
- Structured response parsing from `LM Studio` may be less predictable than in the Python version and needs careful validation.

## Rollout Strategy

1. Add native Swift workflow types and tests alongside the current sidecar path.
2. Add `LangGraph-Swift` graph execution and `LMStudioClient`.
3. Switch `SessionCoordinator` from sidecar invocation to native workflow execution.
4. Re-run build and app-level verification.
5. Remove the Python sidecar once Swift coverage and behavior are proven.

## Success Criteria

- VoiceRaft remains a menu-bar app with the same start/stop flow.
- The app produces professional Obsidian meeting notes without launching a Python sidecar.
- `LM Studio` remains the configurable local LLM backend.
- Judge and revision behavior matches the current product expectations.
- Export, pending-save, and audio-retention guarantees remain intact.
