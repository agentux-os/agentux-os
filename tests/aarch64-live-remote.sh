#!/usr/bin/bash
# Boots an aarch64 live ISO on an ARM host, over SSH, with tests/live-vm.sh.
# GitHub's arm64 runners have no KVM, so the aarch64 ISOs are checked this
# way by hand before a release is approved (see docs/releases/README.md).
#
#   aarch64-live-remote.sh [user@]host ISO [DIR]
#
# ISO is a local file, copied to the host; an https URL the host downloads
# itself; or run:<run id>/<artifact>, an ISO artifact of an agentux-os
# workflow run (a release's, before approval), which the host downloads
# straight from GitHub with a short-lived link this machine gets with `gh`.
# ISO.sha256 (next to the file, at the URL or in the artifact) is checked
# when there is one.
#
# A Linux host needs /dev/kvm and Docker (its user in the `docker` group):
# the test runs in an ubuntu:24.04 container, as on the CI runners, so the
# host needs no QEMU or UEFI firmware of its own. An Apple Silicon Mac runs
# it directly, with HVF and Homebrew's qemu and bash (`brew install qemu
# bash`), kept awake while it runs. The download and the test run there in
# the background, in ~/agentux-aarch64-live, and this script only checks on
# them, so a dropped SSH connection doesn't stop them. The summary, logs and
# screenshots come back to DIR (default: output/aarch64-live).
#
# The install test is off by default (LIVE_TEST_INSTALL=0): installing from
# the live system runs in RAM and needs about 12 GB, so turn it on with
# LIVE_TEST_INSTALL=1 LIVE_TEST_MEMORY=12288 on a host with room for that.
# LIVE_TEST_MEMORY (MiB, default 5120), LIVE_TEST_CPUS (4) and
# LIVE_TEST_VARIANT (cosmic for an agentux-cosmic-* ISO, else plasma) are
# passed on.
set -euo pipefail

host="${1:?usage: aarch64-live-remote.sh [user@]host ISO [DIR]}"
iso="${2:?usage: aarch64-live-remote.sh [user@]host ISO [DIR]}"
dir="${3:-output/aarch64-live}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work=agentux-aarch64-live
repo=agentux-os/agentux-os
case "$iso" in
    run:*/*)
        run="${iso#run:}"
        artifact="${run#*/}"
        run="${run%%/*}"
        name="$artifact.iso"
        ;;
    *) name="$(basename "$iso")" ;;
esac
# The desktop the ISO is for, from its name (agentux-<desktop>-live-...).
case "$name" in
    agentux-cosmic-*) variant="${LIVE_TEST_VARIANT:-cosmic}" ;;
    *) variant="${LIVE_TEST_VARIANT:-plasma}" ;;
esac
install="${LIVE_TEST_INSTALL:-0}"
memory="${LIVE_TEST_MEMORY:-5120}" cpus="${LIVE_TEST_CPUS:-4}"
ssh=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 "$host")

# Retries a short SSH command while the connection drops (exit 255). The
# commands keep to what both bash and zsh (a Mac's login shell) take.
remote() {
    local try rc
    for try in 1 2 3 4 5 6; do
        rc=0
        "${ssh[@]}" "$@" || rc=$?
        [[ $rc -ne 255 ]] && return "$rc"
        echo "ssh to $host dropped; retrying ($try)" >&2
        sleep 10
    done
    return 255
}

os="$(remote uname -s)"
if [[ "$os" == Darwin ]]; then
    remote "[ \"\$(uname -m)\" = arm64 ] && test -x /opt/homebrew/bin/qemu-system-aarch64 -a -x /opt/homebrew/bin/bash" || {
        echo "$host needs Apple Silicon and Homebrew's qemu and bash (brew install qemu bash)" >&2
        exit 1
    }
else
    remote "test -w /dev/kvm && docker info >/dev/null && [ \"\$(uname -m)\" = aarch64 ]" || {
        echo "$host needs aarch64, a writable /dev/kvm and Docker" >&2
        exit 1
    }
fi
remote "test ! -e $work/status -a -e $work/job.sh" && {
    echo "a test is still running on $host (~/$work/job.log); wait for it or remove ~/$work/job.sh" >&2
    exit 1
}
remote "mkdir -p $work/iso $work/repo && rm -rf $work/out $work/status $work/job.sh $work/job.log"

# The tests from this checkout, so a branch can be tried before it merges.
tar -C "$here" -cf - tests | remote "rm -rf $work/repo/tests && tar -C $work/repo -xf -"

# How the host gets the ISO, in the job below.
case "$iso" in
    run:*)
        id="$(gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" \
            -q ".artifacts[] | select(.name == \"$artifact\") | .id")"
        [[ -n "$id" ]] || { echo "run $run has no artifact $artifact" >&2; exit 1; }
        # The redirect to the artifact's storage, valid for about a minute:
        # the job starts right away.
        url="$(curl -fsS -o /dev/null -w '%{redirect_url}' \
            -H "Authorization: Bearer $(gh auth token)" \
            "https://api.github.com/repos/$repo/actions/artifacts/$id/zip")"
        [[ -n "$url" ]] || { echo "no download link for artifact $id" >&2; exit 1; }
        fetch="rm -f ./* && curl -fsSL -o artifact.zip '$url' && unzip -q -o artifact.zip && rm artifact.zip"
        ;;
    https://*)
        # A copy the checksum already matches isn't downloaded again.
        fetch="find . -type f ! -name '$name' ! -name '$name.sha256' -delete
            { curl -fsSL -o '$name.sha256' '$iso.sha256' || rm -f '$name.sha256'; }
            { [ -s '$name.sha256' ] && sha256sum --quiet -c '$name.sha256' 2>/dev/null; } \
                || curl -fsSL -o '$name' '$iso'"
        ;;
    *)
        [[ -f "$iso" ]] || { echo "no such ISO: $iso" >&2; exit 1; }
        remote "find $work/iso -type f -delete"
        scp -q -o BatchMode=yes "$iso" "$host:$work/iso/$name"
        if [[ -f "$iso.sha256" ]]; then
            scp -q -o BatchMode=yes "$iso.sha256" "$host:$work/iso/$name.sha256"
        fi
        fetch=true
        ;;
esac

# The test itself: straight on a Mac, in a container elsewhere.
if [[ "$os" == Darwin ]]; then
    test="export PATH=/opt/homebrew/bin:\$PATH LIVE_TEST_INSTALL=$install LIVE_TEST_MEMORY=$memory \\
    LIVE_TEST_CPUS=$cpus LIVE_TEST_VARIANT=$variant
caffeinate -i bash repo/tests/live-vm.sh 'iso/$name' out/live-test"
else
    test="docker rm -f agentux-aarch64-live >/dev/null 2>&1 || true
docker run --rm --name agentux-aarch64-live --device /dev/kvm \\
    -v \"\$PWD/repo:/repo:ro\" -v \"\$PWD/iso:/iso:ro\" -v \"\$PWD/out:/out\" \\
    -e OWNER=\"\$(id -u):\$(id -g)\" -e LIVE_TEST_INSTALL=$install \\
    -e LIVE_TEST_MEMORY=$memory -e LIVE_TEST_CPUS=$cpus \\
    -e LIVE_TEST_VARIANT=$variant \\
    ubuntu:24.04 bash -c 'apt-get update -qq \\
        && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \\
           qemu-system-arm qemu-utils qemu-efi-aarch64 ipxe-qemu python3 >/dev/null \\
        && { /repo/tests/live-vm.sh \"/iso/$name\" /out/live-test; rc=\$?; chown -R \"\$OWNER\" /out; exit \$rc; }'"
fi

# The job: get the ISO, check it, and test it.
remote "cat > $work/job.sh" <<EOF
set -e
cd ~/$work/iso
$fetch
# The checksum file names the ISO without its directory.
if [ -s '$name.sha256' ]; then sha256sum -c '$name.sha256'; else echo 'no $name.sha256; not checked'; fi
cd ~/$work
$test
EOF
# setsid where there is one; a Mac has none, and nohup is enough there.
remote "cd $work && \$(command -v setsid) nohup bash -c 'bash job.sh; echo \$? > status' >job.log 2>&1 </dev/null &"
echo "testing $name on $host (log: ~/$work/job.log)" >&2

# Wait for it, for up to two hours.
rc=""
for _ in $(seq 1 240); do
    sleep 30
    if rc="$("${ssh[@]}" "cat $work/status 2>/dev/null")" && [[ -n "$rc" ]]; then
        break
    fi
    rc=""
done
if [[ -z "$rc" ]]; then
    echo "the test on $host has not finished after two hours; see ~/$work/job.log there" >&2
    exit 1
fi

# Logs, screenshots and the summary; not the VM's disks or sockets.
mkdir -p "$dir"
remote "cat $work/job.log" >"$dir/job.log" || true
remote "tar -C $work/out/live-test --exclude='*.qcow2' --exclude='*.sock' \
    --exclude=OVMF_VARS.fd --exclude=qemu.pid -cf - ." | tar -C "$dir" -xf - || true
if [[ -f "$dir/summary.md" ]]; then
    cat "$dir/summary.md"
else
    tail -20 "$dir/job.log" >&2
fi
echo "aarch64 live test of $name on $host: exit $rc; results in $dir" >&2
exit "$rc"
