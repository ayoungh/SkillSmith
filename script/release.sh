#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./script/release.sh <version> [options]

Creates a versioned macOS build and publishes it to GitHub Releases.

Arguments:
  <version>       Semantic version (for example, 1.0.0 or 1.0.0-alpha.1)

Options:
  --draft         Create a draft GitHub release
  --prerelease    Mark the GitHub release as a prerelease
  --dry-run       Build and package everything without publishing
  -h, --help      Show this help

Environment:
  CODESIGN_IDENTITY   Developer ID signing identity. Defaults to ad-hoc signing.
USAGE
}

VERSION=""
DRAFT=false
PRERELEASE=false
DRY_RUN=false

while (($# > 0)); do
  case "$1" in
    --draft)
      DRAFT=true
      ;;
    --prerelease)
      PRERELEASE=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "error: only one version may be supplied" >&2
        usage >&2
        exit 2
      fi
      VERSION="${1#v}"
      ;;
  esac
  shift
done

if [[ -z "$VERSION" ]]; then
  echo "error: a release version is required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "error: version must be semantic, for example 1.0.0 or 1.0.0-alpha.1" >&2
  exit 2
fi

if [[ "$VERSION" == *-* ]]; then
  PRERELEASE=true
fi

for command_name in git gh swift codesign ditto shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command '$command_name' was not found" >&2
    exit 1
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SkillSmithApp"
TAG="v$VERSION"
BUNDLE_VERSION="${VERSION%%-*}"
COMMIT="$(git rev-parse HEAD)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ARCHIVE="$DIST_DIR/$APP_NAME-$TAG-macos.zip"
CHECKSUM="$ARCHIVE.sha256"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$DRY_RUN" == false ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: the working tree must be clean before creating a release" >&2
    exit 1
  fi

  gh auth status >/dev/null
  git fetch origin --tags

  if ! git rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    echo "error: the current branch has no upstream branch" >&2
    exit 1
  fi

  if [[ "$(git rev-parse '@{upstream}')" != "$COMMIT" ]]; then
    echo "error: the current branch must exactly match its upstream; push or pull first" >&2
    exit 1
  fi

  if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null ||
     git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 ||
     gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: tag or release '$TAG' already exists" >&2
    exit 1
  fi
fi

echo "Running tests..."
swift test

echo "Building release bundle..."
"$ROOT_DIR/script/package_app.sh" release "$BUNDLE_VERSION" "$BUILD_NUMBER"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Signing app ad hoc. Set CODESIGN_IDENTITY to use a Developer ID certificate."
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  echo "Signing app with '$SIGNING_IDENTITY'..."
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$ARCHIVE" "$CHECKSUM"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$CHECKSUM")"
)

echo "Created:"
echo "  $ARCHIVE"
echo "  $CHECKSUM"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run complete; no tag or GitHub release was created."
  exit 0
fi

GH_ARGS=(
  release create "$TAG"
  "$ARCHIVE#macOS app"
  "$CHECKSUM#SHA-256 checksum"
  --target "$COMMIT"
  --title "SkillSmith $TAG"
  --generate-notes
  --fail-on-no-commits
)

if [[ "$DRAFT" == true ]]; then
  GH_ARGS+=(--draft)
fi

if [[ "$PRERELEASE" == true ]]; then
  GH_ARGS+=(--prerelease)
fi

echo "Publishing $TAG to GitHub Releases..."
gh "${GH_ARGS[@]}"

RELEASE_URL="$(gh release view "$TAG" --json url --jq .url)"
echo "Release published: $RELEASE_URL"
