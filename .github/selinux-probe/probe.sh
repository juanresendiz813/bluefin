#!/bin/bash
# Throwaway: probe one image's SELinux /var/home substitution (ublue-os/bluefin#4976).
# Read-only on the image: everything runs in a --rm container; the candidate fix is
# applied only inside that container to measure before/after.
set -euo pipefail

IMAGE="$1"
OUT="$2"
mkdir -p "$OUT"

df -h / | tail -1
podman pull --quiet "$IMAGE"
podman image inspect --format 'digest={{.Digest}} revision={{index .Labels "org.opencontainers.image.revision"}} version={{index .Labels "org.opencontainers.image.version"}} created={{.Created}}' "$IMAGE" | tee "$OUT/meta.txt"

# SETUP (matrix) is only used by the plain-Fedora control to install the policy RPM.
podman run --rm --entrypoint /bin/bash -e SETUP="${SETUP:-}" "$IMAGE" -c "$(cat <<'EOS'
set -uo pipefail
if [ -n "${SETUP:-}" ]; then echo "## setup: $SETUP"; eval "$SETUP"; fi
SUBS=/etc/selinux/targeted/contexts/files/file_contexts.subs_dist
HOMEDIRS=/etc/selinux/targeted/contexts/files/file_contexts.homedirs

echo "## os-release"; grep -E '^(PRETTY_NAME|VERSION_ID|VARIANT_ID)=' /etc/os-release || true
echo "## /etc/selinux/config"; grep -E '^SELINUX(TYPE)?=' /etc/selinux/config || echo "(none)"
echo "## /etc/default/useradd"; grep '^HOME=' /etc/default/useradd || echo "(none)"

echo "## $SUBS (cat -A: \$ marks line end, ^I is a tab)"
cat -A "$SUBS"
ALT=/usr/etc/selinux/targeted/contexts/files/file_contexts.subs_dist
if [ -e "$ALT" ]; then echo "## $ALT"; cat -A "$ALT"; else echo "## $ALT: absent"; fi

echo "## subs_dist verdict"
if grep -Eq '^/var/home[[:space:]]+/home' "$SUBS"; then V=RPM-ORIGINAL
elif grep -Eq '^/home[[:space:]]+/var/home' "$SUBS"; then V=OSTREE-FIXED
else V=NEITHER; fi
echo "VERDICT=$V"

echo "## rpm -q"; rpm -q selinux-policy selinux-policy-targeted libselinux-utils 2>&1

echo "## rpm -V selinux-policy-targeted, subs_dist line only (empty = byte-identical to the RPM payload)"
rpm -V selinux-policy-targeted 2>/dev/null | grep subs_dist || echo "RPMV_SUBS_DIST=unmodified"

echo "## install times (epoch, date, nevr)"
rpm -q --qf '%{INSTALLTIME} %{INSTALLTIME:date} %{NAME}-%{VERSION}-%{RELEASE}\n' glibc bash selinux-policy selinux-policy-targeted container-selinux 2>&1

echo "## install-time clusters: epoch -> package count (sorted by time)"
rpm -qa --qf '%{INSTALLTIME}\n' | sort | uniq -c | awk '{print $2, $1}' | sort -n | head -60

echo "## packages installed within 60s of selinux-policy-targeted"
T=$(rpm -q --qf '%{INSTALLTIME}' selinux-policy-targeted)
rpm -qa --qf '%{INSTALLTIME} %{NAME}-%{VERSION}-%{RELEASE}\n' | awk -v t="$T" '$1>=t-60 && $1<=t+60' | sort -n

echo "## rpm -qa --last | head -40"; rpm -qa --last | head -40

echo "## installed packages that Require selinux-policy*"
for p in $(rpm -qa --qf '%{NAME}\n' | sort); do
  rpm -q --requires "$p" 2>/dev/null | grep -E '^selinux-policy' | sed "s/^/$p: /"
done | sort -u

echo "## homedirs: count of /var/home rules, count of /home rules, the .ssh lines"
echo "var_home_rules=$(grep -c '^/var/home' "$HOMEDIRS" || true) home_rules=$(grep -c '^/home' "$HOMEDIRS" || true)"
grep -E '\\.ssh' "$HOMEDIRS" || true

echo "## matchpathcon BEFORE"
command -v matchpathcon >/dev/null || echo "matchpathcon missing"
matchpathcon /var/home /var/home/x /var/home/x/.ssh /var/home/x/.ssh/authorized_keys /home/x/.ssh 2>&1 || true
if matchpathcon -n /var/home/x/.ssh 2>/dev/null | grep -q ':ssh_home_t:'; then echo "TEST_BEFORE=PASS"; else echo "TEST_BEFORE=FAIL"; fi

echo "## candidate fix applied INSIDE this throwaway container (rpm-ostree's subs_dist edit)"
sed -i 's|^/var/home[[:space:]]|# &|' "$SUBS"
grep -q '^/home /var/home$' "$SUBS" || echo '/home /var/home' >> "$SUBS"
echo "### subs_dist AFTER"; cat -A "$SUBS"
echo "### matchpathcon AFTER"
matchpathcon /var/home /var/home/x /var/home/x/.ssh /var/home/x/.ssh/authorized_keys 2>&1 || true
if matchpathcon -n /var/home/x/.ssh 2>/dev/null | grep -q ':ssh_home_t:'; then echo "TEST_AFTER=PASS"; else echo "TEST_AFTER=FAIL"; fi
EOS
)" 2>&1 | tee "$OUT/probe.txt"

# Controls on the measurement itself: the verdict line must exist and be one of the known values.
grep -Eq '^VERDICT=(RPM-ORIGINAL|OSTREE-FIXED|NEITHER)$' "$OUT/probe.txt" || { echo "probe produced no verdict" >&2; exit 1; }
grep -q '^TEST_BEFORE=' "$OUT/probe.txt" || { echo "probe produced no TEST_BEFORE" >&2; exit 1; }
echo "probe ok"
