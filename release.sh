#!/usr/bin/env bash
#
# release.sh — Build, tag, and publish OwnTone Sync to Codeberg releases.
#
# Prerequisites:
#   - CODEBERG_TOKEN env var set (generate at https://codeberg.org/user/settings/applications)
#     Required scope: write:repository
#   - flutter, jq, curl on PATH
#   - Clean git working tree
#   - Version already bumped in pubspec.yaml
#
# Usage:
#   export CODEBERG_TOKEN="your-token-here"
#   ./release.sh
#
# Obtainium users can then add: https://codeberg.org/Edu_Coder/owntone-sync

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
CODEBERG_API="https://codeberg.org/api/v1"
REPO_OWNER="Edu_Coder"
REPO_NAME="owntone-sync"
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
for cmd in flutter jq curl git; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not found on PATH."
done

# Load .env if present (won't override existing env vars)
if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
fi

# Check token
[[ -n "${CODEBERG_TOKEN:-}" ]] || die "CODEBERG_TOKEN environment variable is not set.
Generate one at: https://codeberg.org/user/settings/applications
Required scope: write:repository"

# Must be run from project root (where pubspec.yaml lives)
[[ -f "pubspec.yaml" ]] || die "pubspec.yaml not found. Run this script from the project root."

# ── Read version from pubspec.yaml ───────────────────────────────────────────
# Extracts "0.1.0" from "version: 0.1.0+1"
VERSION=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//;s/+.*//')
VERSION_FULL=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//')
TAG="v${VERSION}"
APK_NAME="${APK_PREFIX}-${TAG}.apk"

[[ -n "$VERSION" ]] || die "Could not parse version from pubspec.yaml."

bold "Version:  ${VERSION_FULL}"
bold "Tag:      ${TAG}"
bold "APK name: ${APK_NAME}"
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
echo "  APK:     ${APK_NAME}"
echo
bold "Release notes:"
echo "$RELEASE_NOTES"
echo "─────────────────────────────────────────"
echo
read -rp "Proceed with build and release? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo

# ── Build APK ────────────────────────────────────────────────────────────────
bold "Building release APK..."
flutter build apk --release

# Flutter outputs to a known location
FLUTTER_APK="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$FLUTTER_APK" ]] || die "Expected APK not found at ${FLUTTER_APK}. Build may have failed."

# Copy with versioned name
cp "$FLUTTER_APK" "$APK_NAME"
APK_SIZE=$(du -h "$APK_NAME" | cut -f1)
green "✓ APK built: ${APK_NAME} (${APK_SIZE})"
echo

# ── Create and push git tag ──────────────────────────────────────────────────
bold "Creating git tag ${TAG}..."
git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"
green "✓ Tag ${TAG} pushed to origin."
echo

# ── Create Codeberg release ──────────────────────────────────────────────────
bold "Creating release on Codeberg..."

# Build the JSON payload — jq handles escaping the release notes safely
RELEASE_PAYLOAD=$(jq -n \
    --arg tag "$TAG" \
    --arg name "OwnTone Sync ${TAG}" \
    --arg body "$RELEASE_NOTES" \
    '{
        tag_name: $tag,
        name: $name,
        body: $body,
        draft: false,
        prerelease: false
    }')

MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
    RELEASE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token ${CODEBERG_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$RELEASE_PAYLOAD" \
        "${CODEBERG_API}/repos/${REPO_OWNER}/${REPO_NAME}/releases")

    HTTP_CODE=$(echo "$RELEASE_RESPONSE" | tail -1)
    RELEASE_BODY=$(echo "$RELEASE_RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" -eq 201 ]]; then
        break
    fi

    if [[ "$attempt" -lt "$MAX_RETRIES" ]]; then
        yellow "Attempt ${attempt}/${MAX_RETRIES} failed (HTTP ${HTTP_CODE}). Retrying in 5s..."
        sleep 5
    else
        red "Failed to create release after ${MAX_RETRIES} attempts (HTTP ${HTTP_CODE}):"
        echo "$RELEASE_BODY" | jq . 2>/dev/null || echo "$RELEASE_BODY"
        die "Release creation failed. The tag has been pushed — you may need to create the release manually on Codeberg."
    fi
done

RELEASE_ID=$(echo "$RELEASE_BODY" | jq -r '.id')
RELEASE_URL=$(echo "$RELEASE_BODY" | jq -r '.html_url')

green "✓ Release created: ${RELEASE_URL}"
echo

# ── Upload APK attachment ────────────────────────────────────────────────────
bold "Uploading ${APK_NAME}..."

UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: token ${CODEBERG_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${APK_NAME}" \
    "${CODEBERG_API}/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets?name=${APK_NAME}")

HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 201 ]]; then
    red "Failed to upload APK (HTTP ${HTTP_CODE}):"
    echo "$UPLOAD_BODY" | jq . 2>/dev/null || echo "$UPLOAD_BODY"
    die "APK upload failed. Release was created — upload the APK manually at: ${RELEASE_URL}"
fi

DOWNLOAD_URL=$(echo "$UPLOAD_BODY" | jq -r '.browser_download_url')
green "✓ APK uploaded: ${DOWNLOAD_URL}"

# ── Clean up local APK copy ──────────────────────────────────────────────────
rm -f "$APK_NAME"

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════════"
green "Release ${TAG} published successfully!"
echo
bold "Release page:"
echo "  ${RELEASE_URL}"
echo
bold "Obtainium URL (give this to users):"
echo "  https://codeberg.org/${REPO_OWNER}/${REPO_NAME}"
echo "═══════════════════════════════════════════════════════════════"