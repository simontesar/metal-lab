#!/usr/bin/env bash

# Boot a metalprobe kernel + initramfs under QEMU on a baseline CPU and check
# that it reaches metalprobe-launcher.

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Go to metalprobe-image root directory
cd "$SCRIPT_DIR/.."

TIMEOUT="${BOOT_TEST_TIMEOUT:-300}"

ARCH=""
KERNEL=""
INITRAMFS=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --arch|-a)
    ARCH="$2"
    shift
    shift
    ;;
  --kernel|-k)
    KERNEL="$2"
    shift
    shift
    ;;
  --initramfs|-i)
    INITRAMFS="$2"
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

if [[ "$ARCH" == "" || "$KERNEL" == "" || "$INITRAMFS" == "" ]]; then
  echo "Must specify --arch, --kernel and --initramfs"
  exit 1
fi

case $ARCH in
amd64)
  QEMU=(qemu-system-x86_64 -machine q35 -cpu qemu64)
  FW_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
  FW_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
  CONSOLE=ttyS0
  ;;
arm64)
  QEMU=(qemu-system-aarch64 -machine virt -cpu cortex-a57)
  FW_CODE=/usr/share/AAVMF/AAVMF_CODE.fd
  FW_VARS=/usr/share/AAVMF/AAVMF_VARS.fd
  CONSOLE=ttyAMA0
  ;;
*)
  echo "Unsupported arch $ARCH"
  exit 1
  ;;
esac

mkdir -p ./bin
LOG="./bin/boot-$ARCH.log"
VARS="$(mktemp)"
cp "$FW_VARS" "$VARS"
: > "$LOG"

QEMU_PID=""
cleanup() {
  if [[ -n "$QEMU_PID" ]]; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$VARS"
}
trap cleanup EXIT

"${QEMU[@]}" -accel tcg -m 1024 -smp 1 \
  -nic none -display none -monitor none -no-reboot -serial "file:$LOG" \
  -drive if=pflash,format=raw,readonly=on,file="$FW_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -kernel "$KERNEL" -initrd "$INITRAMFS" -append "console=$CONSOLE" &
QEMU_PID=$!

echo "Booting $KERNEL ($ARCH), timeout ${TIMEOUT}s"
result=TIMEOUT
for (( i = 0; i < TIMEOUT; i++ )); do
  if grep -q 'metalprobe-launcher parking' "$LOG"; then result=PASS; break; fi
  if grep -qE 'Exception Type|Synchronous Exception|Kernel panic' "$LOG"; then result=FAIL; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then result=EXITED; break; fi
  sleep 1
done

echo "Boot test $ARCH: $result ($i s)"
if [[ "$result" != PASS ]]; then
  echo "--- last 50 lines of $LOG ---" >&2
  tail -n 50 "$LOG" >&2
  exit 1
fi
