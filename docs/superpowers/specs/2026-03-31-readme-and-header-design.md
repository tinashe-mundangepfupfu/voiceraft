# VoiceRaft README And Header Design

## Summary

Create a project `README.md` for VoiceRaft and add a custom header image that replaces the usual markdown title. The README should speak to two audiences in one pass:

- Someone deciding whether VoiceRaft is worth using
- A developer deciding whether the project is worth contributing to

The chosen direction is a balanced "builder story" opening: product credibility first, with architecture clarity visible from the top of the page.

## Goals

- Give the repository a polished first impression on GitHub
- Explain VoiceRaft clearly in under a minute
- Highlight the three core product promises together:
  - local-first privacy
  - polished meeting-note quality
  - Obsidian-native export workflow
- Make the project feel intentionally Swift-native after the sidecar removal
- Provide practical setup and development instructions without making the README feel like internal notes

## Non-Goals

- Rebrand the product beyond the README header treatment
- Redesign the app UI itself
- Add marketing claims not supported by the current app behavior
- Turn the README into long-form architecture documentation

## Audience

### Primary audience

Potential users evaluating whether VoiceRaft fits their meeting workflow.

### Secondary audience

Developers evaluating the repository structure, current architecture, and how to run the project locally.

## Chosen Direction

VoiceRaft should open with a custom visual banner instead of a markdown H1. The banner contains the product name and establishes three ideas at once:

- VoiceRaft is a native macOS tool
- The workflow stays local and privacy-aware
- The output is a refined note artifact, not just a raw transcript

The overall README tone should feel calm, confident, and product-grade rather than experimental or overly technical.

## README Structure

The README should follow this sequence:

1. Header image
2. Short product introduction
3. `Why VoiceRaft`
4. `How It Works`
5. `What You Need`
6. `Quick Start`
7. `Architecture`
8. `Development`
9. `Status`

### Section Expectations

#### Header image

- Embedded at the top of the file
- Carries the `VoiceRaft` title inside the image
- Uses descriptive alt text because there will be no markdown H1 above it

#### Short product introduction

- One compact paragraph
- Explains that VoiceRaft is a macOS menu-bar app that records meetings, transcribes locally, uses LM Studio to produce structured notes, and exports to Obsidian

#### `Why VoiceRaft`

- Three concise proof points:
  - local-first processing
  - higher-quality structured notes
  - clean Obsidian handoff

#### `How It Works`

- Simple capture-to-export flow
- Should be readable quickly by both users and developers
- Preferred shape: short ordered list or compact pipeline bullets

#### `What You Need`

- State practical prerequisites only
- Expected items:
  - macOS
  - LM Studio running locally
  - a configured Obsidian vault path

#### `Quick Start`

- Include the shortest reliable build/run path
- Favor `xcodebuild` commands already used in the repository
- Avoid speculative setup steps that are not reflected in the current native app

#### `Architecture`

- Explain the Swift-native flow briefly
- Explicitly note that the Python sidecar has been removed
- Mention the current split between the shipping app code and the package scaffold

#### `Development`

- Include the app build command
- Include package-level test or check commands if they are real and currently part of the repo workflow
- Keep this section practical rather than aspirational

#### `Status`

- Short note about current maturity and direction
- Should acknowledge the native Swift path without overselling roadmap certainty

## Header Asset Design

The header asset should be implemented as an SVG, not a screenshot or raster mockup.

### Why SVG

- Crisp on GitHub at multiple sizes
- Easy to keep readable
- Editable in-repo without external design tools
- Better fit for a composed banner than a generated bitmap

### Visual Direction

- Wide landscape composition sized for GitHub README width
- Deep slate base with cool blue and muted green accents
- Clear title treatment: `VoiceRaft`
- Calm macOS-inspired scene with three visible cues:
  - menu-bar capture state
  - polished meeting-note preview
  - export or vault context

### Readability Requirements

- Strong contrast between text and background
- Title must remain readable when scaled down in GitHub preview
- Supporting copy, if included, must stay minimal and legible
- Decorative details must never compete with the title

### File Placement

Recommended path:

- `docs/assets/readme-header.svg`

## Content Guidelines

- Keep copy concise and concrete
- Avoid hype language
- Prefer language that matches the app's current behavior
- Use the README to unify product story and developer orientation, not to duplicate deeper design docs
- Preserve terminology already used in the repo where it helps continuity:
  - LM Studio
  - Obsidian
  - native Swift
  - menu-bar app

## Risks And Mitigations

### Risk: trying to serve two audiences makes the opening too dense

Mitigation:

- Keep the intro short
- Move technical detail into lower sections
- Let the image carry more of the first impression

### Risk: the header becomes visually attractive but unreadable on GitHub

Mitigation:

- Use SVG
- Keep typography large
- Use high-contrast title placement
- Avoid busy screenshot-style composition

### Risk: the README drifts from current implementation reality

Mitigation:

- Base setup and architecture sections on current files and verified commands only

## Verification

Implementation should be considered complete when:

- `README.md` exists and follows the approved structure
- The top of the README renders the custom header image successfully on GitHub-style markdown
- The header image remains readable at typical repository page widths
- Build and development commands in the README match commands already verified in the repository
