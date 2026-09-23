#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Go to metalprobe-image root directory
cd "$SCRIPT_DIR/.."

U_ROOT="${U_ROOT:-u-root}"
KBAKE="${KBAKE:-kbake}"
U_ROOT_PKG="$(go list -m -f "{{ .Dir }}" github.com/u-root/u-root)"

ARCHS=(amd64 arm64)

KERNEL_TAG=""
INITRAMFS_OUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --kernel-tag|-k)
    KERNEL_TAG="$2"
    shift
    shift
    ;;
  -o)
    INITRAMFS_OUT="$2"
    shift
    shift
    ;;
  -*|--*)
    echo "Unknown option $1"
    exit 1
    ;;
  *)
    echo "No positional arguments allowed"
    exit 1
    ;;
  esac
done

if [[ "$KERNEL_TAG" == "" ]]; then
  echo "Must specify --kernel-tag"
  exit 1
fi

mkdir -p ./bin

ARCH_LIST="$(IFS=,; echo "${ARCHS[*]}")"
"$KBAKE" build . --arch "$ARCH_LIST" -t "metalprobe-kernel:$KERNEL_TAG"

for arch in "${ARCHS[@]}"; do
  "$KBAKE" get kernel "metalprobe-kernel:$KERNEL_TAG" -a "$arch" -o "./bin/vmlinuz-$arch"

  initramfs_opts=()
  if [[ -n "$INITRAMFS_OUT" ]]; then
    base="${INITRAMFS_OUT%.cpio}"
    initramfs_opts+=("-o=${base}-${arch}.cpio")
  fi

  GOOS=linux GOARCH="$arch" CGO_ENABLED=0 "$U_ROOT" \
    -uinitcmd="metalprobe-launcher" \
    -defaultsh="" \
    ${initramfs_opts[@]+"${initramfs_opts[@]}"} \
    "$U_ROOT_PKG"/cmds/core/init \
    github.com/ironcore-dev/metal-operator/cmd/metalprobe \
    ./cmd/metalprobe-launcher
done
