#!/usr/bin/env bash
# Stops while the legal drafts still contain [[PLACEHOLDER]] markers.
# Usage: scripts/check_legal.sh [dir]   (default docs/legal). ALLOW_LEGAL_DRAFT=1 turns the stop into a warning.
set -uo pipefail
dir="${1:-$(dirname "$0")/../docs/legal}"
rc=0
for f in privacy-policy.md terms-of-use.md; do
  p="$dir/$f"
  if [ ! -f "$p" ]; then echo "FAIL  $f is missing in $dir"; rc=1; continue; fi
  n=$(grep -o '\[\[[^]]*\]\]' "$p" | wc -l)
  if [ "$n" -gt 0 ]; then echo "FAIL  $f still has $n [[...]] placeholder(s)"; rc=1; else echo "PASS  $f has no placeholders"; fi
done
if [ "$rc" = 1 ] && [ "${ALLOW_LEGAL_DRAFT:-0}" = 1 ]; then echo "WARN  legal drafts are not final (ALLOW_LEGAL_DRAFT=1): do not take real members yet"; exit 0; fi
exit "$rc"
