#!/usr/bin/env bash
# Acceptance tests for the tap's fyug formula. Run from the repo root:
#   bash tests/acceptance.sh
#
# Network: downloads only from github.com/Ilusiv-media/fyug release assets.
# Safety: never runs `brew`, and never executes any downloaded binary (the
# binaries are only inspected with `otool -L`, and only on macOS).
set -uo pipefail

RELEASE_REPO="Ilusiv-media/fyug"
RELEASE_BASE="https://github.com/${RELEASE_REPO}/releases/download"
SCRATCH_VERSION="2026.11.0" # release used for the update-script test

[ -d Formula ] && [ -d scripts ] || { echo "run from the tap repo root" >&2; exit 2; }
ROOT="$PWD"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
pass() { printf 'PASS %s %s\n' "$1" "$2"; }
fail() { printf 'FAIL %s %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }

sha256_of() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
fetch() { curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }

# Formula under test: Formula/fyug.rb. Fall back to a lone existing formula so
# the other criteria still give a meaningful failure before the rename lands.
FORMULA="Formula/fyug.rb"
if [ ! -f "$FORMULA" ]; then
  fallback="$(ls Formula/*.rb 2>/dev/null | head -n1 || true)"
  FORMULA="${fallback:-$FORMULA}"
fi

# ---- parse the formula ------------------------------------------------------
VERSION=""
if [ -f "$FORMULA" ]; then
  VERSION="$(sed -nE 's/^[[:space:]]*version[[:space:]]+"([^"]+)".*/\1/p' "$FORMULA" | head -n1)"
fi
# "url<TAB>sha256" per line, with #{version} interpolated.
: > "$TMP/pairs.tsv"
if [ -f "$FORMULA" ]; then
  awk -v version="$VERSION" '
    /^[[:space:]]*url[[:space:]]+"/ { u = $0; sub(/^[^"]*"/, "", u); sub(/".*/, "", u); gsub(/#\{version\}/, version, u); next_sha = 1; url = u; next }
    /^[[:space:]]*sha256[[:space:]]+"/ && next_sha { h = $0; sub(/^[^"]*"/, "", h); sub(/".*/, "", h); printf "%s\t%s\n", url, h; next_sha = 0 }
  ' "$FORMULA" > "$TMP/pairs.tsv"
fi

# ---- release metadata (shared by criteria 1-3) -----------------------------
SUMS="$TMP/SHA256SUMS.txt"
HAVE_SUMS=0
if [ -n "$VERSION" ] && fetch "${RELEASE_BASE}/v${VERSION}/SHA256SUMS.txt" "$SUMS" 2>/dev/null; then HAVE_SUMS=1; fi
sum_for() { awk -v want="$1" '{ n = $2; sub(/.*\//, "", n); if (n == want) { print $1; exit } }' "$SUMS"; }

# ---- 1: every URL resolves to an asset of a promoted Ilusiv-media/fyug release
c1_fail=0
if [ ! -f "$FORMULA" ]; then
  fail 1 "no formula found"; c1_fail=1
elif [ -z "$VERSION" ]; then
  fail 1 "no version in $FORMULA"; c1_fail=1
elif [ ! -s "$TMP/pairs.tsv" ]; then
  fail 1 "no url/sha256 pairs found in $FORMULA"; c1_fail=1
else
  prefix="${RELEASE_BASE}/v${VERSION}/"
  if [ "$(wc -l < "$TMP/pairs.tsv" | tr -d ' ')" -lt 3 ]; then
    fail 1 "expected 3 url/sha256 pairs (macOS arm, linux arm, linux x86_64), found $(wc -l < "$TMP/pairs.tsv" | tr -d ' ')"; c1_fail=1
  fi
  page="$TMP/release.html"
  code="$(curl -sL --proto '=https' -o "$page" -w '%{http_code}' "https://github.com/${RELEASE_REPO}/releases/tag/v${VERSION}" || true)"
  if [ "$code" != "200" ]; then
    fail 1 "release v${VERSION} of ${RELEASE_REPO} is not published (tag page HTTP $code)"; c1_fail=1
  elif grep -qi 'Pre-release' "$page"; then
    fail 1 "release v${VERSION} is marked Pre-release (not promoted)"; c1_fail=1
  fi
  while IFS=$'\t' read -r url _; do
    case "$url" in
      "$prefix"*) ;;
      *) fail 1 "url is not under ${prefix}: $url"; c1_fail=1; continue ;;
    esac
    asset="${url#"$prefix"}"
    if [ "$HAVE_SUMS" = 1 ] && [ -z "$(sum_for "$asset")" ]; then
      fail 1 "$asset is not listed in release v${VERSION} SHA256SUMS.txt"; c1_fail=1; continue
    fi
    status="$(curl -sIL --proto '=https' -o /dev/null -w '%{http_code}' "$url" || true)"
    if [ "$status" != "200" ]; then fail 1 "url does not resolve (HTTP $status): $url"; c1_fail=1; fi
  done < "$TMP/pairs.tsv"
fi
[ "$c1_fail" = 0 ] && pass 1 "all formula URLs resolve to assets of promoted ${RELEASE_REPO} release v${VERSION}"

# ---- 2: every sha256 matches the release's SHA256SUMS.txt -------------------
c2_fail=0
if [ "$HAVE_SUMS" != 1 ]; then
  fail 2 "could not fetch ${RELEASE_BASE}/v${VERSION:-?}/SHA256SUMS.txt"; c2_fail=1
elif [ ! -s "$TMP/pairs.tsv" ]; then
  fail 2 "no url/sha256 pairs found in $FORMULA"; c2_fail=1
else
  while IFS=$'\t' read -r url hash; do
    asset="${url##*/}"
    want="$(sum_for "$asset")"
    if [ -z "$want" ]; then fail 2 "$asset has no entry in SHA256SUMS.txt"; c2_fail=1
    elif [ "$want" != "$hash" ]; then fail 2 "$asset: formula has $hash, SHA256SUMS.txt has $want"; c2_fail=1; fi
  done < "$TMP/pairs.tsv"
fi
[ "$c2_fail" = 0 ] && pass 2 "every formula sha256 matches SHA256SUMS.txt of v${VERSION}"

# ---- 3: ruby -c, and otool -L of the installed binaries ---------------------
c3_fail=0
if [ ! -f "$FORMULA" ]; then
  fail 3 "no formula to syntax-check"; c3_fail=1
elif ! ruby -c "$FORMULA" >/dev/null 2>"$TMP/ruby.err"; then
  fail 3 "ruby -c failed: $(head -n1 "$TMP/ruby.err")"; c3_fail=1
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "SKIP 3 otool -L part (not macOS)"
else
  mac_url="$(awk -F'\t' '$1 ~ /aarch64-apple-darwin\.tar\.gz$/ {print $1; exit}' "$TMP/pairs.tsv")"
  case "$mac_url" in
    "") fail 3 "formula has no aarch64-apple-darwin url to inspect"; c3_fail=1 ;;
    "${RELEASE_BASE}/"*)
      ex="$TMP/extract"; mkdir -p "$ex"
      if ! fetch "$mac_url" "$TMP/mac.tar.gz"; then
        fail 3 "could not download $mac_url"; c3_fail=1
      elif tar -tzf "$TMP/mac.tar.gz" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
        fail 3 "archive has unsafe paths; not extracting"; c3_fail=1
      else
        tar -xzf "$TMP/mac.tar.gz" -C "$ex"
        # Installed names come from the formula's bin.install line.
        names="$(sed -nE 's/^[[:space:]]*bin\.install[[:space:]]+(.*)$/\1/p' "$FORMULA" | grep -v '=>' | grep -oE '"[^"]+"' | tr -d '"')"
        for n in $names; do
          [ -f "$ex/$n" ] || { fail 3 "formula installs \"$n\" but the archive has no such file at its root"; c3_fail=1; }
        done
        macho=0
        while IFS= read -r f; do
          out="$(otool -L "$f" 2>/dev/null)" || continue
          macho=$((macho + 1))
          bad="$(printf '%s\n' "$out" | grep -E '^[[:space:]]' | sed -E 's/^[[:space:]]+//; s/ \(.*$//' | grep -vE '^(/System/Library/|/usr/lib/)' || true)"
          if [ -n "$bad" ]; then
            fail 3 "unexpected dylibs in ${f#"$ex"/}: $(printf '%s' "$bad" | tr '\n' ' ')"; c3_fail=1
          fi
        done < <(find "$ex" -type f)
        [ "$macho" -gt 0 ] || { fail 3 "no Mach-O binaries found in the macOS archive"; c3_fail=1; }
      fi ;;
    *) fail 3 "macOS url is not a ${RELEASE_REPO} release asset, not downloading: $mac_url"; c3_fail=1 ;;
  esac
fi
[ "$c3_fail" = 0 ] && pass 3 "ruby -c passes and binaries link only /System/Library and /usr/lib"

# ---- 4: comments no longer mention the install script -----------------------
if [ ! -f "$FORMULA" ]; then fail 4 "no formula found"
elif hits="$(grep -nEi 'install\.sh|install script' "$FORMULA")"; then
  fail 4 "$FORMULA still mentions the install script: $(printf '%s' "$hits" | head -n2 | tr '\n' '|')"
else
  pass 4 "formula has no install.sh / install script mention"
fi

# ---- 5: named fyug, old fugue installs migrate ------------------------------
c5_fail=0
[ -f Formula/fyug.rb ] || { fail 5 "Formula/fyug.rb does not exist"; c5_fail=1; }
if [ -f Formula/fyug.rb ] && ! grep -qE '^class Fyug < Formula' Formula/fyug.rb; then fail 5 "Formula/fyug.rb does not define class Fyug < Formula"; c5_fail=1; fi
[ ! -e Formula/fugue.rb ] || { fail 5 "Formula/fugue.rb still exists"; c5_fail=1; }
if [ ! -f formula_renames.json ]; then
  fail 5 "formula_renames.json missing at the tap root"; c5_fail=1
else
  got="$(ruby -rjson -e 'puts JSON.parse(File.read("formula_renames.json"))["fugue"].inspect' 2>/dev/null || echo PARSE_ERROR)"
  [ "$got" = '"fyug"' ] || { fail 5 "formula_renames.json maps \"fugue\" to $got, expected \"fyug\""; c5_fail=1; }
fi
[ "$c5_fail" = 0 ] && pass 5 "formula is Formula/fyug.rb (class Fyug), fugue.rb is gone, rename map migrates fugue -> fyug"

# ---- 6: update-formula.sh rewrites Formula/fyug.rb from Ilusiv-media/fyug ---
c6_fail=0
if [ ! -f Formula/fyug.rb ] || [ ! -f scripts/update-formula.sh ]; then
  fail 6 "need Formula/fyug.rb and scripts/update-formula.sh"; c6_fail=1
else
  scratch="$TMP/scratch"; mkdir -p "$scratch/Formula" "$scratch/scripts"
  cp scripts/update-formula.sh "$scratch/scripts/"
  # Stale the scratch formula so a no-op script cannot pass.
  sed -E 's/^([[:space:]]*version[[:space:]]+")[^"]*"/\11999.1.1"/; s/^([[:space:]]*sha256[[:space:]]+")[0-9a-fA-F]+"/\10000000000000000000000000000000000000000000000000000000000000000"/' \
    Formula/fyug.rb > "$scratch/Formula/fyug.rb"
  cp "$scratch/Formula/fyug.rb" "$TMP/stale.rb"
  if ! (cd "$scratch" && env -u REPO -u FORMULA bash scripts/update-formula.sh "$SCRATCH_VERSION" >"$TMP/update.log" 2>&1); then
    fail 6 "update-formula.sh $SCRATCH_VERSION failed: $(tail -n1 "$TMP/update.log")"; c6_fail=1
  else
    out="$scratch/Formula/fyug.rb"
    fetch "${RELEASE_BASE}/v${SCRATCH_VERSION}/SHA256SUMS.txt" "$TMP/sums6.txt" || { fail 6 "could not fetch SHA256SUMS.txt"; c6_fail=1; }
    got_v="$(sed -nE 's/^[[:space:]]*version[[:space:]]+"([^"]+)".*/\1/p' "$out" | head -n1)"
    [ "$got_v" = "$SCRATCH_VERSION" ] || { fail 6 "version after update is '$got_v', expected $SCRATCH_VERSION"; c6_fail=1; }
    awk -v version="$got_v" '
      /^[[:space:]]*url[[:space:]]+"/ { u = $0; sub(/^[^"]*"/, "", u); sub(/".*/, "", u); gsub(/#\{version\}/, version, u); n = 1; url = u; next }
      /^[[:space:]]*sha256[[:space:]]+"/ && n { h = $0; sub(/^[^"]*"/, "", h); sub(/".*/, "", h); printf "%s\t%s\n", url, h; n = 0 }
    ' "$out" > "$TMP/pairs6.tsv"
    [ -s "$TMP/pairs6.tsv" ] || { fail 6 "no url/sha256 pairs in updated formula"; c6_fail=1; }
    while IFS=$'\t' read -r url hash; do
      case "$url" in "${RELEASE_BASE}/v${SCRATCH_VERSION}/"*) ;; *) fail 6 "updated url not under ${RELEASE_REPO} v${SCRATCH_VERSION}: $url"; c6_fail=1 ;; esac
      asset="${url##*/}"
      want="$(awk -v want="$asset" '{ n = $2; sub(/.*\//, "", n); if (n == want) { print $1; exit } }' "$TMP/sums6.txt")"
      [ -n "$want" ] && [ "$want" = "$hash" ] || { fail 6 "$asset: updated formula has $hash, SHA256SUMS.txt has '${want:-<none>}'"; c6_fail=1; }
    done < "$TMP/pairs6.tsv"
    # Only version and sha256 lines may change.
    other="$(diff <(grep -vE '^[[:space:]]*(version|sha256)[[:space:]]+"' "$TMP/stale.rb") <(grep -vE '^[[:space:]]*(version|sha256)[[:space:]]+"' "$out") || true)"
    [ -z "$other" ] || { fail 6 "update script changed lines other than version/sha256"; c6_fail=1; }
    ruby -c "$out" >/dev/null 2>&1 || { fail 6 "updated formula fails ruby -c"; c6_fail=1; }
  fi
fi
[ "$c6_fail" = 0 ] && pass 6 "update-formula.sh $SCRATCH_VERSION (default REPO/FORMULA) rewrites version and hashes to match SHA256SUMS.txt"

echo
if [ "$FAILS" -gt 0 ]; then echo "$FAILS failure(s)"; exit 1; fi
echo "all criteria passed"
