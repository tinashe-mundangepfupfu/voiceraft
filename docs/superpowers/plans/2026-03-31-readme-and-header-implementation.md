# VoiceRaft README And Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a polished `README.md` and a readable custom SVG header that present VoiceRaft to both users and contributors.

**Architecture:** Keep the implementation small and repo-native: a hand-authored SVG banner under `docs/assets/` and a top-level `README.md` that moves from product story to practical setup and architecture. Base all claims on the current native Swift app and only include development commands that are verified in this workspace.

**Tech Stack:** Markdown, SVG, GitHub README rendering, `xcodebuild`, `swift test`, shell verification commands

---

### Task 1: Create the header asset

**Files:**
- Create: `docs/assets/readme-header.svg`
- Verify: `docs/assets/readme-header.svg`

- [ ] **Step 1: Draft the SVG composition**

Create a wide banner that includes:
- the `VoiceRaft` title inside the image
- a calm macOS-inspired interface scene
- visible cues for local recording, note quality, and Obsidian export
- high-contrast typography that stays readable on GitHub

- [ ] **Step 2: Check the SVG for readability-oriented structure**

Run: `sed -n '1,240p' docs/assets/readme-header.svg`
Expected: title text, supporting labels, and visual groups are clearly represented in the markup.

### Task 2: Write the README

**Files:**
- Create: `README.md`
- Modify: `docs/assets/readme-header.svg`

- [ ] **Step 1: Write the README sections in approved order**

Include:
- header image embed at the top
- short introduction
- `Why VoiceRaft`
- `How It Works`
- `What You Need`
- `Quick Start`
- `Architecture`
- `Development`
- `Status`

- [ ] **Step 2: Ground commands and claims in the current repo**

Use only commands and statements that match the native Swift app and current package scaffold.

- [ ] **Step 3: Verify the README content directly**

Run: `sed -n '1,260p' README.md`
Expected: sections appear in the approved order and the header image is embedded from `docs/assets/readme-header.svg`.

### Task 3: Verify and clean up

**Files:**
- Modify: `README.md`
- Modify: `docs/assets/readme-header.svg`
- Delete: `.superpowers/` temporary brainstorming screens

- [ ] **Step 1: Verify the package checks if they are documented**

Run: `swift test --package-path Packages/VoiceRaftCore`
Expected: PASS if the README includes the package test command. If it fails, remove or qualify that command in the README.

- [ ] **Step 2: Verify the app build command**

Run: `xcodebuild -project voiceraft.xcodeproj -scheme voiceraft -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Remove temporary brainstorming artifacts**

Run: `rm -rf .superpowers`
Expected: the temporary browser companion files are gone from the working tree.

- [ ] **Step 4: Check the resulting diff**

Run: `git status --short`
Expected: only intended README/header changes remain alongside the existing in-flight native Swift changes.
