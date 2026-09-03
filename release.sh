#!/usr/bin/env bash
#
# release.sh — Build, tag, and publish OwnTone Sync to GitHub releases.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login) with access to
#     jptrsn/owntone-sync
#   - flutter, git on PATH
#   - Clean git working tree
#   - Version already bumped in pubspec.yaml
#
# Usage:
#   ./release.sh
#
# Obtainium users can then add: https://github.com/jptrsn/owntone-sync

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
GH_REPO="jptrsn/owntone-sync"
APK_PREFIX="owntone-sync"

# ── Helpers ──────────────────────────────────────────────────────────────────
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

die() { red "ERROR: $*" >&2; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────────────
bold "=== OwnTone Sync Release ==="
echo

# Check dependencies
for cmd in flutter gh git; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not found on PATH."
done

# Check gh auth
gh auth status &>/dev/null || die "gh CLI is not authenticated. Run: gh auth login"

# Must be run from project root (where pubspec.yaml lives)
[[ -f "pubspec.yaml" ]] || die "pubspec.yaml not found. Run this script from the project root."

# ── Read version from pubspec.yaml ───────────────────────────────────────────
# Extracts "0.1.0" from "version: 0.1.0+1"
VERSION=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//;s/+.*//')
VERSION_FULL=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//')
TAG="v${VERSION}"

[[ -n "$VERSION" ]] || die "Could not parse version from pubspec.yaml."

bold "Version:  ${VERSION_FULL}"
bold "Tag:      ${TAG}"
bold "APKs:     ${APK_PREFIX}-${TAG}-{arm64-v8a,armeabi-v7a,x86_64}.apk"
echo

# ── Check git is clean ───────────────────────────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
    die "Git working tree is dirty. Commit or stash your changes first."
fi

# ── Check tag doesn't already exist ──────────────────────────────────────────
if git rev-parse "$TAG" &>/dev/null 2>&1; then
    die "Tag '${TAG}' already exists locally. Bump the version in pubspec.yaml first."
fi

if git ls-remote --tags origin "refs/tags/${TAG}" | grep -q "${TAG}"; then
    die "Tag '${TAG}' already exists on the remote. Bump the version in pubspec.yaml first."
fi

green "✓ Preflight checks passed."
echo

# ── Collect release notes ────────────────────────────────────────────────────
bold "Enter release notes (press Ctrl-D on an empty line when done):"
echo
RELEASE_NOTES=$(cat)
echo

if [[ -z "$RELEASE_NOTES" ]]; then
    die "Release notes cannot be empty."
fi

# Show summary and confirm
echo "─────────────────────────────────────────"
bold "Release summary:"
echo "  Tag:     ${TAG}"
echo "  Version: ${VERSION_FULL}"
echo "  APKs:    ${APK_PREFIX}-${TAG}-arm64-v8a.apk"
echo "           ${APK_PREFIX}-${TAG}-armeabi-v7a.apk"
echo "           ${APK_PREFIX}-${TAG}-x86_64.apk"
echo
bold "Release notes:"
echo "$RELEASE_NOTES"
echo "─────────────────────────────────────────"
echo
read -rp "Proceed with build and release? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo

# ── Build APKs ───────────────────────────────────────────────────────────────
bold "Building release APKs (split per ABI)..."
flutter build apk --release --split-per-abi

# Flutter outputs per-abi APKs to a known location
FLUTTER_APK_DIR="build/app/outputs/flutter-apk"

# Rename and collect APKs (bash 3.2 compatible — no associative arrays)
APK_FILES=""
for abi in arm64-v8a armeabi-v7a x86_64; do
    src="${FLUTTER_APK_DIR}/app-${abi}-release.apk"
    dest="${APK_PREFIX}-${TAG}-${abi}.apk"
    [[ -f "$src" ]] || die "Expected APK not found: ${src}"
    cp "$src" "$dest"
    APK_FILES="${APK_FILES} ${dest}"
    APK_SIZE=$(du -h "$dest" | cut -f1)
    echo "  ${dest} (${APK_SIZE})"
done
green "✓ APKs built."
echo

# ── Create and push git tag ──────────────────────────────────────────────────
bold "Creating git tag ${TAG}..."
git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"
green "✓ Tag ${TAG} pushed to origin."
echo

# ── Create GitHub release ────────────────────────────────────────────────────
bold "Creating release on GitHub..."

# gh release create in one call: creates the release from the tag we just
# pushed (--verify-tag makes it fail loudly instead of inventing its own tag
# if that push somehow didn't land) and uploads all the APKs as release
# assets. --notes-file - reads the release notes straight from stdin, so no
# temp file is needed.
gh release create "$TAG" \
    --repo "$GH_REPO" \
    --title "OwnTone Sync ${TAG}" \
    --notes-file - \
    --verify-tag \
    $APK_FILES <<< "$RELEASE_NOTES" \
    || die "Release creation/upload failed. The tag has been pushed — you may need to create the release manually on GitHub."

RELEASE_URL=$(gh release view "$TAG" --repo "$GH_REPO" --json url --jq '.url')

green "✓ Release created: ${RELEASE_URL}"
echo

# ── Clean up local APK copies ────────────────────────────────────────────────
rm -f $APK_FILES

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════════"
green "Release ${TAG} published successfully!"
echo
bold "Release page:"
echo "  ${RELEASE_URL}"
echo
bold "Obtainium URL (give this to users):"
echo "  https://github.com/${GH_REPO}"
echo "═══════════════════════════════════════════════════════════════"
