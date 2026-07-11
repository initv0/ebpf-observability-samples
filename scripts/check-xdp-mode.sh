#!/usr/bin/env bash
#
# check-xdp-mode.sh
#
# XDP's performance profile changes by an order of magnitude between NATIVE mode
# (the program runs in the NIC driver) and GENERIC mode (it runs later in the
# stack, when the driver has no native XDP support). This reports the driver per
# interface and how to confirm native support, so you know what you're actually
# benchmarking before you trust any packets-per-second number.
set -euo pipefail

for path in /sys/class/net/*; do
  dev=$(basename "$path")
  [ "$dev" = "lo" ] && continue

  driver="unknown"
  if command -v ethtool >/dev/null 2>&1; then
    driver=$(ethtool -i "$dev" 2>/dev/null | awk -F': ' '/^driver:/{print $2}')
  elif [ -e "$path/device/driver" ]; then
    driver=$(basename "$(readlink -f "$path/device/driver")")
  fi

  echo "== ${dev} (driver: ${driver:-unknown}) =="

  # Kernel 6.3+ advertises an xdp-features bitmap over netlink; recent iproute2
  # prints it. If shown, NATIVE support is what you're looking for in the list.
  feats=$(ip -d link show "$dev" 2>/dev/null | grep -oiE 'xdp[a-z_-]*' | sort -u | tr '\n' ' ')
  [ -n "$feats" ] && echo "  reported: ${feats}"

  echo "  definitive test (needs a built XDP object):"
  echo "    sudo ip link set dev ${dev} xdpdrv obj <prog.o> sec xdp   # error => no NATIVE XDP"
  echo "    sudo ip link set dev ${dev} xdpgeneric obj <prog.o> sec xdp   # generic fallback (slow)"
done

echo
echo "Re-check after any driver or kernel upgrade — native XDP support is"
echo "driver-specific and can regress silently."
