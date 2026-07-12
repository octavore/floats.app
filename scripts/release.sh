#!/usr/bin/env bash
# Bumps app.version in strudel.toml, commits, and tags the release.
# Usage: scripts/release.sh [major|minor|patch]  (default: patch)
set -euo pipefail

cd "$(dirname "$0")/.."

bump="${1:-patch}"
case "$bump" in
  major|minor|patch) ;;
  *)
    echo "usage: $0 [major|minor|patch]" >&2
    exit 1
    ;;
esac

current="$(sed -nE 's/^app\.version *= *"([0-9]+\.[0-9]+\.[0-9]+)"/\1/p' strudel.toml)"
if [[ -z "$current" ]]; then
  echo "error: could not find app.version in strudel.toml" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<<"$current"
case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac
new="$major.$minor.$patch"
tag="v$new"

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "error: tag $tag already exists" >&2
  exit 1
fi

build_number="$(sed -nE 's/^app\.build_number *= *"([0-9]+)"/\1/p' strudel.toml)"
new_build_number=$((build_number + 1))

read -r -p "Bump $current -> $new and tag $tag? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

sed -i '' -E \
  -e "s/^app\.version *= *\"$current\"/app.version              = \"$new\"/" \
  -e "s/^app\.build_number *= *\"$build_number\"/app.build_number      = \"$new_build_number\"/" \
  strudel.toml

git add strudel.toml
git commit -m "release: $tag"
git tag "$tag"

echo "Bumped $current -> $new, tagged $tag."
echo "Push with: git push && git push origin $tag"
