#!/usr/bin/env bash
# Usage: next-version.sh [REV]
# Prints the next version from Conventional Commits since the last v* tag as key=value
# lines (version, previous, bump, release), and appends them to $GITHUB_OUTPUT when set.
set -euo pipefail

rev="${1:-HEAD}"

previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$rev" 2>/dev/null || true)"
if [[ -n "$previous" ]]; then
  range="${previous}..${rev}"
  base="${previous#v}"
else
  range="$rev"
  base="0.0.0"
fi

core="${base%%[-+]*}"
IFS=. read -r major minor patch <<<"$core"

subjects="$(git log --format=%s "$range")"
bodies="$(git log --format=%b "$range")"

bump="none"
if grep -Eq '^[a-z]+(\([^)]*\))?!:' <<<"$subjects" || grep -Eq '^BREAKING[ -]CHANGE:' <<<"$bodies"; then
  bump="major"
elif grep -Eq '^feat(\([^)]*\))?:' <<<"$subjects"; then
  bump="minor"
elif grep -Eq '^(fix|perf|revert)(\([^)]*\))?:' <<<"$subjects"; then
  bump="patch"
fi

case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

release="true"
[[ "$bump" == "none" ]] && release="false"
version="${major}.${minor}.${patch}"
[[ "$release" == "false" ]] && version="$core"

out="version=${version}
previous=${previous#v}
bump=${bump}
release=${release}"
printf '%s\n' "$out"
[[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s\n' "$out" >> "$GITHUB_OUTPUT"
exit 0
