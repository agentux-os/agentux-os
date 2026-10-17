#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2 $3" == 'release list --repo' ]]; then
    [[ "$4" == agentux-os/agentux-core ]] && { echo v0.4.3; exit; }
    [[ "$4" == agentux-os/agentux-desktop ]] && { echo v0.5.2; exit; }
fi
if [[ "$1 $2" == 'release view' ]]; then
    while IFS= read -r asset; do
        [[ "$asset" == "${MOCK_MISSING:-}" ]] || echo "$asset"
    done < <(
        for arch in x86_64 aarch64; do
            printf 'agentux-0.4.3-1.fc44.%s.rpm\nagentux-cockpit-0.5.2-1.%s.rpm\n' "$arch" "$arch"
        done
        for bundle in common plasma cosmic; do
            printf 'agentux-desktop-%s-0.5.2.tar.gz\nagentux-desktop-%s-0.5.2.tar.gz.sha256\n' "$bundle" "$bundle"
        done
    )
    exit 0
fi
if [[ "$1 $2" == 'release download' ]]; then
    pattern=
    while (($#)); do
        [[ "$1" == --pattern ]] && { pattern=$2; break; }
        shift
    done
    [[ "$pattern" == "${MOCK_MISSING:-}" ]] && exit 1
    printf '%064d  %s\n' 0 "${pattern%.sha256}"
    exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 2
MOCK
chmod +x "$tmp/bin/gh"

cat > "$tmp/Containerfile.template" <<'CONTAINERFILE'
ARG AGENTUX_CORE_VERSION=0.4.2
ARG AGENTUX_DESKTOP_VERSION=0.5.1
ARG AGENTUX_COMMON_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ARG AGENTUX_PLASMA_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
ARG AGENTUX_COSMIC_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
CONTAINERFILE

assets=(
  agentux-desktop-common-0.5.2.tar.gz
  agentux-desktop-common-0.5.2.tar.gz.sha256
  agentux-desktop-plasma-0.5.2.tar.gz
  agentux-desktop-plasma-0.5.2.tar.gz.sha256
  agentux-desktop-cosmic-0.5.2.tar.gz
  agentux-desktop-cosmic-0.5.2.tar.gz.sha256
  agentux-cockpit-0.5.2-1.x86_64.rpm
  agentux-cockpit-0.5.2-1.aarch64.rpm
  agentux-0.4.3-1.fc44.x86_64.rpm
  agentux-0.4.3-1.fc44.aarch64.rpm
)
for missing in "${assets[@]}"; do
    cp "$tmp/Containerfile.template" "$tmp/Containerfile"
    before=$(sha256sum "$tmp/Containerfile")
    if PATH="$tmp/bin:$PATH" MOCK_MISSING="$missing" AGENTUX_CONTAINERFILE="$tmp/Containerfile" "$root/.github/scripts/bump-agentux.sh" >/dev/null 2>&1; then
        echo "bump unexpectedly accepted missing asset: $missing" >&2
        exit 1
    fi
    after=$(sha256sum "$tmp/Containerfile")
    [[ "$before" == "$after" ]] || { echo "Containerfile changed despite missing $missing" >&2; exit 1; }
done

cp "$tmp/Containerfile.template" "$tmp/Containerfile"
PATH="$tmp/bin:$PATH" AGENTUX_CONTAINERFILE="$tmp/Containerfile" "$root/.github/scripts/bump-agentux.sh" >/dev/null
grep -qx 'ARG AGENTUX_CORE_VERSION=0.4.3' "$tmp/Containerfile"
grep -qx 'ARG AGENTUX_DESKTOP_VERSION=0.5.2' "$tmp/Containerfile"
grep -qx 'ARG AGENTUX_COMMON_SHA256=0000000000000000000000000000000000000000000000000000000000000000' "$tmp/Containerfile"
echo 'bump-agentux atomic preflight: OK'
