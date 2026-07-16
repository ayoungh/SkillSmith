# SkillSmith

A native macOS app for managing the agent skills on your machine — discover, install, author, and update skills across Claude Code, Codex, Cursor, Gemini CLI, and any other agent that reads a skills directory.

<p align="center">
  <img src="Assets/icon-source.png" alt="SkillSmith icon" width="160">
</p>

## What it does

- **Discovers every skill on your machine** by scanning the well-known agent roots (`~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`, `~/.cursor/skills`, `~/.gemini/skills`) plus any custom roots you add. Symlinked installs are resolved and deduplicated, so a skill shared across agents shows up once — with badges for every agent it's installed in.
- **Integrates with [skills.sh](https://skills.sh)** (the Vercel skills CLI): browse a repository's available skills, pull them in globally, and update everything with one click.
- **Reads SKILL.md in place** so you can see exactly what a skill instructs before installing or removing it.
- **Installs and removes per agent** — symlink a skill into any agent root, or remove a single install without touching the source.
- **Authors new skills** from a template, or drafts them with AI (bring your own OpenAI API key, stored in the macOS Keychain).
- **Tracks upstream repositories** and shows a full diff preview before you apply an update.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build
- Node.js with `npx` on your PATH — used for the skills.sh CLI integration (optional; the app degrades gracefully without it)

## Build and run

```sh
./script/build_and_run.sh
```

This builds the app with SwiftPM, assembles `dist/SkillSmithApp.app` with its icon and Info.plist, and launches it. Other modes:

```sh
./script/build_and_run.sh --debug      # run under lldb
./script/build_and_run.sh --logs       # run and stream unified logs
./script/build_and_run.sh --verify     # run and assert the process started
```

Or use plain SwiftPM during development:

```sh
swift build
swift test
```

## Create a GitHub release

Install and authenticate the [GitHub CLI](https://cli.github.com/), then commit
and push your changes. Create a release by passing the new version:

```sh
./script/release.sh 1.0.0
```

The script runs the test suite, creates an optimized and versioned macOS app
bundle, signs it, produces a zip and SHA-256 checksum, and publishes both files
to a new GitHub Release with generated release notes.

By default the app is ad-hoc signed. To use a Developer ID certificate:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./script/release.sh 1.0.0
```

Useful release modes:

```sh
./script/release.sh 1.0.0 --dry-run
./script/release.sh 1.0.0 --draft
./script/release.sh 1.0.0 --prerelease
```

The script does not notarize the app, so macOS may warn people who download it,
even when it is Developer ID signed.

## Project layout

```
App/        App entry point and menu commands
Models/     Value types: skills, agent roots, install targets, settings
Stores/     Observable app state and persistence (Application Support/SkillSmith)
Services/   Filesystem scanning, skills.sh CLI, git diffing, Keychain, AI drafting
Support/    Paths, symlink resolution, SKILL.md frontmatter parsing
Views/      SwiftUI views
Tests/      Swift Testing suite
script/     Build and packaging script
Assets/     App icon artwork
```

## How it works

SkillSmith treats the filesystem as the source of truth. On every refresh it:

1. Asks the skills.sh CLI (`npx skills ls -g --json`) for installed skills and their agent metadata.
2. Scans each agent root for skill directories (anything containing a `SKILL.md`), resolving symlinks to their canonical source.
3. Merges both by skill name into a single record with one install target per agent root, pruning anything that no longer exists on disk.

App state is persisted to `~/Library/Application Support/SkillSmith/state.json`. API keys live only in the macOS Keychain.

## Contributing

Issues and pull requests are welcome. Before submitting, run `swift test` and make sure `./script/build_and_run.sh --verify` passes.

## License

[MIT](LICENSE)
