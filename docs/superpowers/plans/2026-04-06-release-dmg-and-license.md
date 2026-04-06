# Release DMG And License Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a semver-driven GitHub release pipeline that builds a macOS `.dmg`, optionally signs and notarizes it when Apple credentials are configured, and make the repository ready for open-source publication under MIT.

**Architecture:** Keep versioning simple and explicit by treating Git tags like `v1.2.3` as the release source of truth. Use a GitHub Actions workflow plus shell scripts to build the app with `xcodebuild`, package a versioned `.dmg`, create or update the GitHub Release, and conditionally enable signing/notarization when secrets are present.

**Tech Stack:** GitHub Actions, zsh/bash shell scripts, xcodebuild, hdiutil, codesign, xcrun notarytool, Swift source-level regression checks, Markdown docs

---

## File Map

- `.github/workflows/release.yml`
  Adds the semver-tag-triggered release workflow for build, optional signing/notarization, and GitHub Release upload.
- `scripts/build-release-dmg.sh`
  Builds the Release app and packages `VoiceRaft-vX.Y.Z.dmg`.
- `scripts/sign-and-notarize.sh`
  Imports optional Apple credentials, signs the app and DMG, notarizes, and staples when secrets are available.
- `tools/release_pipeline_check.swift`
  Source-level regression check that asserts the workflow, scripts, license, and docs are present and wired together.
- `LICENSE`
  MIT license for open-source distribution.
- `README.md`
  Documents semver release tags, DMG packaging, and optional notarization secrets.

### Task 1: Add Release Regression Check

**Files:**
- Create: `tools/release_pipeline_check.swift`

- [ ] **Step 1: Write the failing source-level regression check**
- [ ] **Step 2: Run the check to verify it fails before the workflow/scripts/license exist**
- [ ] **Step 3: Commit**

### Task 2: Add Release Packaging Scripts And Workflow

**Files:**
- Create: `scripts/build-release-dmg.sh`
- Create: `scripts/sign-and-notarize.sh`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Implement Release app build plus versioned DMG packaging**
- [ ] **Step 2: Implement optional signing/notarization helper that no-ops safely when secrets are absent**
- [ ] **Step 3: Add a semver-tag-triggered GitHub Actions workflow that creates/uploads Releases**
- [ ] **Step 4: Re-run the regression check**
- [ ] **Step 5: Commit**

### Task 3: Add MIT License And Release Documentation

**Files:**
- Create: `LICENSE`
- Modify: `README.md`

- [ ] **Step 1: Add MIT license text**
- [ ] **Step 2: Document release tagging and optional Apple signing/notarization setup**
- [ ] **Step 3: Re-run the regression check**
- [ ] **Step 4: Run build/script verification**
- [ ] **Step 5: Commit**
