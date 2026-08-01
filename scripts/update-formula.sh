#!/usr/bin/env bash
# Update Formula/fugue.rb to a published gdamron/fugue release.
#
# Rewrites the formula's `version` and the three `fugue-tools-*` sha256 lines
# from the release's SHA256SUMS.txt. The download URLs are derived from
# `version` in the formula, so they update automatically once `version` changes.
#
# Usage: scripts/update-formula.sh <version>
#   <version>  release version without the leading v (e.g. 2026.7.0)
#
# Environment overrides:
#   FORMULA   path to the formula        (default: Formula/fugue.rb)
#   REPO      GitHub repo to pull from    (default: gdamron/fugue)

set -euo pipefail

VERSION="${1:?version required (e.g. 2026.7.0); usage: update-formula.sh <version>}"
VERSION="${VERSION#v}" # tolerate a leading v
FORMULA="${FORMULA:-Formula/fugue.rb}"
REPO="${REPO:-gdamron/fugue}"

[ -f "$FORMULA" ] || { echo "error: formula not found at $FORMULA" >&2; exit 1; }

# The targets the formula ships, in the order their sha256 lines appear. Each
# must have a matching `fugue-tools-<target>.tar.gz` entry in SHA256SUMS.txt.
TARGETS="aarch64-apple-darwin aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SUMS_URL="https://github.com/${REPO}/releases/download/v${VERSION}/SHA256SUMS.txt"
echo "==> Fetching $SUMS_URL"
curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/SHA256SUMS.txt" "$SUMS_URL" \
  || { echo "error: could not fetch SHA256SUMS.txt for v${VERSION} (is the release published?)" >&2; exit 1; }

# Look up the checksum for one fugue-tools target, matching on the basename so
# the leading dist/client-binaries/ path prefix is irrelevant.
sha_for() {
  local target="$1" asset="fugue-tools-$1.tar.gz" hash
  hash="$(awk -v want="$asset" '{ n = $2; sub(/.*\//, "", n); if (n == want) { print $1; exit } }' "$TMP/SHA256SUMS.txt")"
  [ -n "$hash" ] || { echo "error: no checksum for $asset in SHA256SUMS.txt" >&2; exit 1; }
  printf '%s' "$hash"
}

# Build a "target hash" table in a file awk can read (avoids passing newlines
# through awk -v, which BSD awk rejects).
: > "$TMP/map.txt"
for t in $TARGETS; do
  printf '%s %s\n' "$t" "$(sha_for "$t")" >> "$TMP/map.txt"
done

echo "==> Rewriting $FORMULA to v${VERSION}"
# Update `version "..."`, then for each `url ".../fugue-tools-<target>.tar.gz"`
# line, replace the following `sha256 "..."` with that target's hash.
awk -v version="$VERSION" -v mapfile="$TMP/map.txt" '
BEGIN {
  while ((getline line < mapfile) > 0) {
    split(line, f, " ")
    hashes[f[1]] = f[2]
  }
  close(mapfile)
}
/^[[:space:]]*version[[:space:]]+"/ {
  sub(/"[^"]*"/, "\"" version "\"")
  print; next
}
match($0, /fugue-tools-[a-z0-9_-]+\.tar\.gz/) {
  asset = substr($0, RSTART, RLENGTH)
  target = asset; sub(/^fugue-tools-/, "", target); sub(/\.tar\.gz$/, "", target)
  pending = target
  print; next
}
/^[[:space:]]*sha256[[:space:]]+"/ && pending != "" {
  if (!(pending in hashes)) { print "no hash for target " pending > "/dev/stderr"; exit 1 }
  sub(/"[0-9a-fA-F]*"/, "\"" hashes[pending] "\"")
  pending = ""
  print; next
}
{ print }
' "$FORMULA" > "$TMP/formula.rb"

mv "$TMP/formula.rb" "$FORMULA"

echo "==> Updated. Changed lines:"
grep -nE '^\s*(version|sha256)\s+"' "$FORMULA" | sed 's/^/  /'
