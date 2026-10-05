# Local build and test of the AgentUX image. Needs Linux with podman;
# `iso`, `qcow2` and `boot-test` need sudo; `vm` and `boot-test` need qemu with
# KVM and OVMF.

image := env("AGENTUX_IMAGE", "localhost/agentux:dev")
bib := "quay.io/centos-bootc/bootc-image-builder:latest"
hadolint := "docker.io/hadolint/hadolint:v2.15.1"

default:
    @just --list

# Build the image into your podman storage
build:
    podman build --tag {{ image }} .

# Build an Anaconda installer ISO from the local image (output/bootiso/install.iso)
iso: (_bib "anaconda-iso" "disk_config/iso.toml")

# Build a qcow2 disk from the local image; config adds a user, e.g. [[customizations.user]]
qcow2 config="": (_bib "qcow2" config)

# Boot the ISO onto output/vm-disk.qcow2 (iso), boot that disk (disk), or boot output/qcow2/disk.qcow2 (qcow2)
vm target="iso":
    #!/usr/bin/env bash
    set -euo pipefail
    ovmf=""
    for f in /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/qemu/OVMF.fd; do
        [[ -e "$f" ]] && { ovmf="$f"; break; }
    done
    [[ -n "$ovmf" ]] || { echo "OVMF firmware not found; install edk2-ovmf (Fedora) or ovmf (Debian/Ubuntu)" >&2; exit 1; }
    args=(-machine q35,accel=kvm -cpu host -smp 4 -m 8192 -bios "$ovmf"
          -device virtio-vga -display gtk -nic user,model=virtio-net-pci)
    case "{{ target }}" in
        iso)
            # The installer writes to output/vm-disk.qcow2; boot it again later with target=disk.
            [[ -e output/vm-disk.qcow2 ]] || qemu-img create -f qcow2 output/vm-disk.qcow2 64G
            qemu-system-x86_64 "${args[@]}" -boot d -cdrom output/bootiso/install.iso \
                -drive file=output/vm-disk.qcow2,if=virtio ;;
        disk)
            qemu-system-x86_64 "${args[@]}" -drive file=output/vm-disk.qcow2,if=virtio ;;
        qcow2)
            qemu-system-x86_64 "${args[@]}" -snapshot -drive file=output/qcow2/disk.qcow2,if=virtio ;;
        *)
            echo "target must be iso, disk or qcow2" >&2; exit 1 ;;
    esac

# Run the image as a container, do a real first login and check every tool resolves (needs network)
smoke:
    podman run --rm -v "$PWD/tests:/tests:ro,z" {{ image }} /tests/smoke.sh

# Boot the local image in a headless QEMU/KVM VM and run tests/boot.sh over SSH (uses sudo; results in output/boot-test)
boot-test: _boot-config (_bib "qcow2" "output/boot-test/config.toml")
    tests/boot-vm.sh run output/qcow2/disk.qcow2 {{ image }} output/boot-test

_boot-config:
    tests/boot-vm.sh config output/boot-test

# Run shellcheck on the scripts and hadolint on the Containerfile
lint:
    shellcheck files/usr/libexec/agentux/* files/etc/profile.d/agentux.sh tests/*.sh
    podman run --rm -v "$PWD:/src:ro,z" -w /src {{ hadolint }} hadolint Containerfile

# Move the AgentUX pins in the Containerfile to the latest releases (pre-releases included, x86_64 and aarch64 RPMs required); needs gh
bump-agentux:
    #!/usr/bin/env bash
    set -euo pipefail
    latest() {
        gh release list --repo "agentux-os/$1" --exclude-drafts --limit 1             --json tagName --jq '.[0].tagName | ltrimstr("v")'
    }
    core="$(latest agentux-core)"
    desktop="$(latest agentux-desktop)"
    sha="$(gh release download "v$desktop" --repo agentux-os/agentux-desktop         --pattern "agentux-plasma-$desktop.tar.gz.sha256" --output - | cut -d' ' -f1)"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "bad sha256 for agentux-plasma-$desktop: $sha" >&2; exit 1; }
    # The image is built for amd64 and arm64, so both releases need both RPMs.
    assets() { gh release view "v$2" --repo "agentux-os/$1" --json assets --jq '.assets[].name'; }
    core_assets="$(assets agentux-core "$core")"
    desktop_assets="$(assets agentux-desktop "$desktop")"
    missing=()
    for arch in x86_64 aarch64; do
        grep -qxF "agentux-$core-1.fc44.$arch.rpm" <<<"$core_assets" || missing+=("agentux-core v$core: agentux-$core-1.fc44.$arch.rpm")
        grep -qxF "agentux-cockpit-$desktop-1.$arch.rpm" <<<"$desktop_assets" || missing+=("agentux-desktop v$desktop: agentux-cockpit-$desktop-1.$arch.rpm")
    done
    if (( ${#missing[@]} )); then printf 'missing release asset %s\n' "${missing[@]}" >&2; exit 1; fi
    sed -i         -e "s/^ARG AGENTUX_CORE_VERSION=.*/ARG AGENTUX_CORE_VERSION=$core/"         -e "s/^ARG AGENTUX_DESKTOP_VERSION=.*/ARG AGENTUX_DESKTOP_VERSION=$desktop/"         -e "s/^ARG AGENTUX_PLASMA_SHA256=.*/ARG AGENTUX_PLASMA_SHA256=$sha/"         Containerfile
    echo "agentux-core $core, agentux-desktop $desktop (plasma sha256 $sha)"
    git diff --stat -- Containerfile

# Run bootc-image-builder (rootful) on the local image
_bib type config:
    #!/usr/bin/env bash
    set -euo pipefail
    # bootc-image-builder reads the image from root's container storage.
    if [[ "$(id -u)" -ne 0 ]]; then
        podman save {{ image }} | sudo podman load
    fi
    mkdir -p output
    config_args=()
    if [[ -n "{{ config }}" ]]; then
        config_args=(-v "$(realpath "{{ config }}"):/config.toml:ro")
    fi
    sudo podman run --rm -it --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        "${config_args[@]}" \
        -v "$PWD/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        {{ bib }} \
        --type {{ type }} \
        --rootfs btrfs \
        --use-librepo=True \
        --chown "$(id -u):$(id -g)" \
        {{ image }}
