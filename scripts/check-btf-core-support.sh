#!/usr/bin/env bash
#
# check-btf-core-support.sh
#
# Pre-flight for CO-RE (Compile Once, Run Everywhere). CO-RE relies on BTF (BPF
# Type Format) being present in the RUNNING kernel so a program compiled once can
# adjust to that kernel's actual struct layouts at load time. Most distros ship
# BTF on 5.x+, but older, minimal/embedded, or heavily customized kernels strip
# it. Run this on your ACTUAL target hosts, not just a dev VM.
set -euo pipefail

echo "host:    $(uname -n)"
echo "kernel:  $(uname -r)"
echo

# 1) The single most important check: is vmlinux BTF exposed?
if [ -r /sys/kernel/btf/vmlinux ]; then
  size=$(wc -c < /sys/kernel/btf/vmlinux 2>/dev/null || echo '?')
  echo "[ok]      /sys/kernel/btf/vmlinux present (${size} bytes) -> CO-RE supported"
else
  echo "[MISSING] /sys/kernel/btf/vmlinux not found"
  echo "          CO-RE will not work here without bundling BTF or building per-kernel."
fi

# 2) Is the JIT on? (interpreted BPF is far slower and disabled on some hardening profiles)
jit=$(cat /proc/sys/net/core/bpf_jit_enable 2>/dev/null || echo '?')
echo "bpf_jit_enable: ${jit}   (1 = on, 2 = on+debug, 0 = off)"

# 3) Kernel lockdown can block bpf() entirely in confidentiality mode.
if [ -r /sys/kernel/security/lockdown ]; then
  echo "lockdown: $(cat /sys/kernel/security/lockdown)"
fi

# 4) If the kernel config is readable, confirm the relevant options are compiled in.
cfg=""
[ -r /proc/config.gz ] && cfg="zcat /proc/config.gz"
[ -r "/boot/config-$(uname -r)" ] && cfg="cat /boot/config-$(uname -r)"
if [ -n "$cfg" ]; then
  echo
  echo "== kernel config (BPF / BTF) =="
  eval "$cfg" | grep -E 'CONFIG_(BPF_SYSCALL|BPF_JIT|DEBUG_INFO_BTF|BPF_LSM)=' || echo "  (relevant options not found)"
fi
