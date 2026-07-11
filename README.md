# ebpf-observability-samples

Runnable reference samples for **kernel-level observability and security with eBPF** —
ad hoc tracing with bpftrace, runtime enforcement with Tetragon, and identity-aware network
policy with Cilium. No sidecars in the data path.

Companion to the article: **[eBPF in Production: Kernel-Level Observability and
Security](https://vkafed.com/ebpf-in-production-kernel-level-observability-and-security/)**
by [Val Kafedzhy](https://vkafed.com).

> This is **reference material**. Everything here runs as-is on a suitable kernel, but the
> policies are deliberately small and single-purpose so you can read them. Adapt the paths,
> labels, and CIDRs to your environment, and test in a lab before anything touches production.
> eBPF programs run in kernel space — treat loading them as the privileged operation it is.

## The idea

Attach eBPF programs directly to kernel hook points on every node, and let a single node
agent per concern do the userspace coordination — Cilium for networking, Tetragon for runtime
security. Policy and identity live in BPF maps the kernel reads on every packet or syscall;
the agent updates those maps live, so a policy change propagates in milliseconds instead of a
rolling proxy restart. No per-pod proxy anywhere.

```
   Pods/processes (no sidecar proxy in the data path)
          |               |                |
     syscalls/exec    network I/O      file/socket ops
          |               |                |
   +------v------+  +-----v------+   +-----v------+
   | kprobes/    |  | XDP (NIC)  |   | LSM hooks  |
   | tracepoints |  | tc (egress)|   | (exec/file)|
   +------|------+  +-----|------+   +-----|------+
          |                |                |
   +------v----------------v----------------v------+
   |         eBPF programs (verified, JIT'd)        |
   +------|-----------------------------------|-----+
          |                                    |
    ring buffer (events)                hash maps (policy/identity/state)
          |                                    |
          +----------------+-------------------+
                           |
                  Node agent (Cilium / Tetragon)
```

## What's here

| Path | What it is |
|---|---|
| `bpftrace/tcp-retransmits-by-comm.bt` | The article's one-liner as a script: count TCP retransmissions per process, live, with no agent and no app changes. Fastest way to find which service is actually retransmitting during an incident. |
| `bpftrace/runqueue-latency.bt` | Complementary scheduler-latency histogram (time a task waits runnable-but-not-running) — the signal that separates "the network is slow" from "the box is oversubscribed." |
| `tetragon/block-shadow-read.yaml` | The article's `TracingPolicy`: hooks the LSM function `security_file_permission` and `SIGKILL`s any process that touches `/etc/shadow`, regardless of syscall. Enforcement, not an after-the-fact alert. |
| `tetragon/audit-network-egress.yaml` | Observe-only companion: records outbound `tcp_connect` calls with process context. Start here (audit) before you switch anything to `Sigkill`. |
| `cilium/l3l4-default-deny.yaml` | A `CiliumNetworkPolicy` that flips a namespace to default-deny and then allows only what's declared — the baseline every Zero Trust east-west story starts from. |
| `cilium/l7-http-visibility.yaml` | Identity-aware L7 policy: allow a client identity to reach only specific HTTP methods/paths on a service, enforced in-kernel by identity rather than IP. |
| `scripts/check-btf-core-support.sh` | Pre-flight for CO-RE: confirms `/sys/kernel/btf/vmlinux` exists and reports kernel/BTF/JIT status on the host you actually run it on. |
| `scripts/check-xdp-mode.sh` | Reports whether each NIC can run **native** XDP (in the driver) or only **generic** XDP (later in the stack) — an order-of-magnitude difference you want to know before you benchmark. |

## Usage

**bpftrace** (ad hoc, nothing to deploy):
```bash
sudo bpftrace bpftrace/tcp-retransmits-by-comm.bt
sudo bpftrace bpftrace/runqueue-latency.bt
```

**Tetragon** (runtime security; install Tetragon first):
```bash
# Audit first — watch what would match, kill nothing:
kubectl apply -f tetragon/audit-network-egress.yaml
kubectl exec -it -n kube-system ds/tetragon -- tetra getevents -o compact
# Then enforce:
kubectl apply -f tetragon/block-shadow-read.yaml
```

**Cilium** (network policy; requires a Cilium-CNI cluster):
```bash
kubectl apply -f cilium/l3l4-default-deny.yaml
kubectl apply -f cilium/l7-http-visibility.yaml
cilium hubble observe --namespace demo --verdict DROPPED   # watch the deny take effect
```

**Readiness checks** (run on the target hosts, not a dev VM):
```bash
sudo scripts/check-btf-core-support.sh
sudo scripts/check-xdp-mode.sh
```

## What's intentionally *not* here

No hand-rolled CO-RE C program. If you need a compiled libbpf/CO-RE skeleton (`.bpf.c` +
loader + `vmlinux.h` + Makefile), start from the upstream that stays current with the toolchain
rather than a copy that rots: **[libbpf/libbpf-bootstrap](https://github.com/libbpf/libbpf-bootstrap)**.
The point this repo makes is the one from the article — for most teams, the right first move
is bpftrace and mature agents (Cilium, Tetragon, Falco, Pixie), not a bespoke program you now
own the verifier debugging for.

## Requirements

- Linux kernel 5.x+ with BTF (`/sys/kernel/btf/vmlinux`) for CO-RE — check with the script, on real hosts
- `bpftrace` for the tracing samples
- A Kubernetes cluster with **Cilium** as CNI for the network policies
- **Tetragon** installed for the runtime-security policies
- `CAP_BPF` / `CAP_PERFMON` (or `CAP_SYS_ADMIN` on older kernels) to load programs — restrict who has it

## Related

- Article: [eBPF in Production](https://vkafed.com/ebpf-in-production-kernel-level-observability-and-security/)
- Decision guide: [Service Mesh vs eBPF-Native Data Planes](https://vkafed.com/service-mesh-vs-ebpf-native-data-planes-how-to-choose/)
- More: [vkafed.com/category/cloud-platform-networking](https://vkafed.com/category/cloud-platform-networking/)

## License

MIT — see [LICENSE](LICENSE).
