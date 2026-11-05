#!/usr/bin/bash
# Boot-tests an aarch64 live ISO on an ARM host with KVM, over SSH, with
# tests/live-vm.sh. GitHub's arm64 runners have no KVM, so the aarch64 ISOs
# are checked this way by hand before a release is approved (see
# docs/releases/README.md).
#
#   aarch64-live-remote.sh [user@]host ISO [DIR]
#
# ISO is a local file, copied to the host, or an https URL the host downloads
# itself; ISO.sha256 (next to the file, or at the URL) is checked when there
# is one. The host needs /dev/kvm and Docker (its user in the `docker`
# group): the test runs in an ubuntu:24.04 container, as on the CI runners,
# so the host needs no QEMU or UEFI firmware of its own. Its work directory is
# ~/agentux-aarch64-live. The summary and screenshots come back to DIR
# (default: output/aarch64-live).
#
# The install test is off (LIVE_TEST_INSTALL=0): installing from the live
# system runs in RAM and needs about 12 GB. LIVE_TEST_MEMORY (MiB, default
# 5120), LIVE_TEST_CPUS (4) and LIVE_TEST_VARIANT (cosmic for an
# agentux-cosmic-* ISO, else plasma) are passed on.
set -euo pipefail

host="${1:?usage: aarch64-live-remote.sh [user@]host ISO [DIR]}"
iso="${2:?usage: aarch64-live-remote.sh [user@]host ISO [DIR]}"
dir="${3:-output/aarch64-live}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work=agentux-aarch64-live
name="$(basename "$iso")"
ssh=(ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=10 "$host")
# The desktop the ISO is for, from its name (agentux-<desktop>-live-...).
case "$name" in
    agentux-cosmic-*) variant="${LIVE_TEST_VARIANT:-cosmic}" ;;
    *) variant="${LIVE_TEST_VARIANT:-plasma}" ;;
esac

"${ssh[@]}" "test -w /dev/kvm && docker info >/dev/null && [ \"\$(uname -m)\" = aarch64 ]" || {
    echo "$host needs aarch64, a writable /dev/kvm and Docker" >&2
    exit 1
}
"${ssh[@]}" "mkdir -p $work/iso $work/repo && rm -rf $work/out"

# The tests from this checkout, so a branch can be tried before it merges.
tar -C "$here" -cf - tests | "${ssh[@]}" "rm -rf $work/repo/tests && tar -C $work/repo -xf -"

if [[ "$iso" == https://* ]]; then
    # A copy the checksum already matches isn't downloaded again.
    "${ssh[@]}" "cd $work/iso && find . -type f ! -name '$name' ! -name '$name.sha256' -delete \
        && { curl -fsSL -o '$name.sha256' '$iso.sha256' || rm -f '$name.sha256'; } \
        && { [ -s '$name.sha256' ] && sha256sum --quiet -c '$name.sha256' 2>/dev/null \
             || curl -fsSL -o '$name' '$iso'; }"
else
    [[ -f "$iso" ]] || { echo "no such ISO: $iso" >&2; exit 1; }
    "${ssh[@]}" "rm -f $work/iso/*"
    scp -q -o BatchMode=yes -o ServerAliveInterval=30 "$iso" "$host:$work/iso/$name"
    if [[ -f "$iso.sha256" ]]; then
        scp -q -o BatchMode=yes -o ServerAliveInterval=30 "$iso.sha256" "$host:$work/iso/$name.sha256"
    fi
fi
# The checksum file names the ISO without its directory.
"${ssh[@]}" "cd $work/iso && if [ -s '$name.sha256' ]; then sha256sum -c '$name.sha256'; else echo 'no $name.sha256; not checked'; fi"

rc=0
"${ssh[@]}" "docker rm -f agentux-aarch64-live >/dev/null 2>&1; cd $work && docker run --rm --name agentux-aarch64-live \
    --device /dev/kvm -v \"\$PWD/repo:/repo:ro\" -v \"\$PWD/iso:/iso:ro\" -v \"\$PWD/out:/out\" \
    -e OWNER=\"\$(id -u):\$(id -g)\" -e LIVE_TEST_INSTALL=0 -e LIVE_TEST_MEMORY=${LIVE_TEST_MEMORY:-5120} \
    -e LIVE_TEST_CPUS=${LIVE_TEST_CPUS:-4} -e LIVE_TEST_VARIANT=$variant \
    ubuntu:24.04 bash -c 'apt-get update -qq \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
           qemu-system-arm qemu-utils qemu-efi-aarch64 ipxe-qemu python3 >/dev/null \
        && /repo/tests/live-vm.sh \"/iso/$name\" /out/live-test; rc=\$?; \
        chown -R \"\$OWNER\" /out; exit \$rc'" || rc=$?

# Logs, screenshots and the summary; not the VM's disks or sockets.
mkdir -p "$dir"
"${ssh[@]}" "tar -C $work/out/live-test --exclude='*.qcow2' --exclude='*.sock' \
    --exclude=OVMF_VARS.fd --exclude=qemu.pid -cf - ." | tar -C "$dir" -xf - || true
if [[ -f "$dir/summary.md" ]]; then cat "$dir/summary.md"; fi
echo "aarch64 live test of $name on $host: exit $rc; results in $dir" >&2
exit "$rc"
