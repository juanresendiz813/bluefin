#!/bin/bash
# Throwaway: render one markdown row per probed image from the probe artifacts.
set -euo pipefail
ART="$1"

echo "| id | version | policy-targeted | subs_dist | rpm -V subs_dist | ~/.ssh before | test before | ~/.ssh after fix | test after |"
echo "|---|---|---|---|---|---|---|---|---|"
for d in "$ART"/*/; do
  id=$(basename "$d")
  [ "$id" = summary ] && continue
  p="$d/probe.txt"
  m="$d/meta.txt"
  if [ ! -f "$p" ]; then echo "| $id | (no probe output) | | | | | | | |"; continue; fi
  ver=$(sed -n 's/.*version=\([^ ]*\).*/\1/p' "$m" 2>/dev/null | head -1)
  pol=$(grep -m1 '^selinux-policy-targeted-' "$p" || echo '?')
  verdict=$(sed -n 's/^VERDICT=//p' "$p" | head -1)
  rpmv=$(grep -m1 'subs_dist' "$p" | grep -v '^##' | grep -E '^(RPMV|[.SM5DLUGTP?]{9})' | head -1 || true)
  rpmv=${rpmv:-$(sed -n 's/^RPMV_SUBS_DIST=//p' "$p" | head -1)}
  before=$(awk '/^## matchpathcon BEFORE/{f=1;next} /^## candidate/{f=0} f && $1=="/var/home/x/.ssh"{print $2}' "$p" | head -1)
  tb=$(sed -n 's/^TEST_BEFORE=//p' "$p" | head -1)
  after=$(awk '/^### matchpathcon AFTER/{f=1;next} f && $1=="/var/home/x/.ssh"{print $2}' "$p" | head -1)
  ta=$(sed -n 's/^TEST_AFTER=//p' "$p" | head -1)
  echo "| $id | ${ver:-?} | ${pol#selinux-policy-targeted-} | ${verdict:-?} | ${rpmv:-?} | ${before:-?} | ${tb:-?} | ${after:-?} | ${ta:-?} |"
done
