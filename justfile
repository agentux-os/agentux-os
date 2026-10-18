# Local build and test of the AgentUX image. Needs Linux with podman;
# `iso`, `qcow2` and `boot-test` need sudo; `vm` and `boot-test` need qemu with
# KVM and OVMF.

image := env("AGENTUX_IMAGE", "localhost/agentux:dev")
bib := "quay.io/centos-bootc/bootc-image-builder:latest"
hadolint := "docker.io/hadolint/hadolint:v2.15.1"
titanoboa := "ghcr.io/ublue-os/titanoboa:latest"

default:
    @just --list

# Build the image into podman's storage; COSMIC resolves Fedora's nightly Atomic base for this host architecture.
build variant="plasma":
    if [ "{{ variant }}" = cosmic ]; then \
        case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) echo "unsupported host architecture" >&2; exit 2 ;; esac; \
        base="$(.github/scripts/resolve-cosmic-base.sh "$arch")"; \
        podman build --build-arg VARIANT=cosmic --build-arg "BASE_IMAGE=$base" --tag {{ image }} .; \
    else \
        podman build --build-arg VARIANT={{ variant }} --tag {{ image }} .; \
    fi

# Build an Anaconda installer ISO from the local image (output/bootiso/install.iso)
iso: (_bib "anaconda-iso" "disk_config/iso.toml")

# Build the live ISO (output/live/*.iso) with Titanoboa from an image: the published one, or e.g. image=localhost/agentux:dev
live image="ghcr.io/agentux-os/agentux:latest":
    #!/usr/bin/env bash
    set -euo pipefail
    # The live layer is built rootful: Titanoboa reads root's container storage.
    if [[ "{{ image }}" == localhost/* && "$(id -u)" -ne 0 ]]; then
        podman save {{ image }} | sudo podman load
    fi
    sudo podman build --build-arg BASE_IMAGE={{ image }} -f live/Containerfile --tag localhost/agentux-live:dev .
    mkdir -p output/live
    sudo podman run --rm --security-opt label=disable \
        -v "$PWD/output/live:/output" \
        -v /var/lib/containers/storage:/usr/lib/containers/storage:ro \
        --mount type=image,source=localhost/agentux-live:dev,dst=/rootfs \
        {{ titanoboa }}
    sudo chown "$(id -u):$(id -g)" output/live/*.iso
    # x86_64: legacy BIOS boot too, with the live image's GRUB (as live.yml).
    if [[ "$(uname -m)" == x86_64 ]]; then
        grub="$(mktemp -d)"
        sudo podman run --rm --security-opt label=disable -v "$grub:/out" localhost/agentux-live:dev \
            sh -euc 'cp -r /usr/lib/grub/i386-pc /out/ && grub2-mkimage -O i386-pc-eltorito -d /usr/lib/grub/i386-pc -o /out/eltorito.img -p /boot/grub2 iso9660 biosdisk'
        sudo chown -R "$(id -u):$(id -g)" "$grub"
        for iso in output/live/*.iso; do
            live/bios-iso.sh "$iso" "$iso.bios" "$grub" && mv "$iso.bios" "$iso"
        done
        rm -rf "$grub"
    fi
    ls -lh output/live/*.iso

# Boot the live ISO headless in QEMU/KVM and test it like CI does (results in output/live-test; LIVE_TEST_INSTALL=0 skips the install, LIVE_TEST_FIRMWARE=bios boots SeaBIOS)
live-test iso="":
    #!/usr/bin/env bash
    set -euo pipefail
    iso="{{ iso }}"
    [[ -n "$iso" ]] || iso="$(ls -t output/live/*.iso | head -n1)"
    tests/live-vm.sh "$iso" output/live-test

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
    shellcheck files/usr/libexec/agentux/* files/etc/profile.d/agentux.sh tests/*.sh .github/scripts/*.sh scripts/*.sh live/build.sh live/files/usr/libexec/agentux/*
    shellcheck --shell=sh live/livesys-session-extra
    podman run --rm -v "$PWD:/src:ro,z" -w /src {{ hadolint }} hadolint Containerfile live/Containerfile

# Move AgentUX release pins only after all RPM, bundle, and checksum assets are verified; needs gh
bump-agentux:
    .github/scripts/bump-agentux.sh

# Preview the notes of a release (e.g. just release-notes v0.5.8); highlights come from docs/releases/<tag>.md; needs gh
release-notes tag:
    .github/scripts/release-notes.sh {{ tag }}

# Tag a release of main's HEAD (e.g. just release 0.5.2) once main has published its image; release.yml then tests it and waits for approval
release version:
    scripts/release.sh {{ version }}

# Approve the release run waiting in the `release` environment (promotes to :stable and publishes the ISOs)
approve:
    scripts/approve.sh

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
