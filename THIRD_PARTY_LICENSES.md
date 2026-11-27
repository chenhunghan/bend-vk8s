# Third-party software in a vk8s release

A vk8s release holds the `vk8s` binary and the guest assets its VMs,
node containers and native nodes run. vk8s itself is Apache-2.0
([LICENSE](LICENSE), [NOTICE](NOTICE)). The guest assets hold the
programs below, each unchanged from its origin and under its own license.
Each input is pinned by a hash in this repository, and the release
[`guest-inputs`](https://github.com/chenhunghan/bend-vk8s/releases/tag/guest-inputs)
keeps a copy of each as its origin served it (docs/RELEASE.md).

The versions are those of the tree this file is in: `scripts/guest/pins.sh`,
`scripts/guest/kernel.sh`, `scripts/guest/fetch-assets.sh` and
`scripts/guest/debs.lock` are the source of truth.

## Linked into the vk8s binary

| Component | License | Source |
|---|---|---|
| bend-kube-runtime | MIT | https://github.com/chenhunghan/bend-kube |
| bend-vmm | MIT | https://github.com/chenhunghan/bend-vmm |

vk8s loads OpenSSL 3 at run time. A Linux host uses its own. For macOS
the arm64 release carries `libssl.3.dylib.tgz` and
`libcrypto.3.dylib.tgz` (OpenSSL 3.5.9, Apache-2.0, as built by
Homebrew's `openssl@3`; its license is the release's
`LICENSE-openssl.txt`; source: https://github.com/openssl/openssl).

## Kernel and boot image (`Image`, `vk8s.cpio`)

| Component | Version | License | Source |
|---|---|---|---|
| Linux kernel | 6.18.65 | GPL-2.0-only | kernel.org's `linux-6.18.tar.xz` with `patch-6.18.65.xz`, built with the config of `main/linux-lts` in [Alpine's aports](https://gitlab.alpinelinux.org/alpine/aports); `scripts/guest/kernel.sh` pins each by hash and builds it |
| BusyBox (static) | Alpine v3.24's `busybox-static` | GPL-2.0-only | https://busybox.net/downloads/ with `main/busybox` of aports, at the commit in the package's `.PKGINFO` |

## Kubernetes and the container runtime (the `node`, `control-plane`, `etcd` and `classic` sets)

From the release bundle of https://github.com/loft-sh/kubernetes
v1.36.6 (Apache-2.0), unchanged:

| Component | Version | License | Source |
|---|---|---|---|
| Kubernetes (kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kubeadm, kubectl) | v1.36.6 | Apache-2.0 | https://github.com/kubernetes/kubernetes |
| etcd (etcd, etcdctl, etcdutl) | v3.6.16 | Apache-2.0 | https://github.com/etcd-io/etcd |
| kine | v0.14.16.vcluster.4 | Apache-2.0 | https://github.com/loft-sh/kine |
| konnectivity | v0.34.0 | Apache-2.0 | https://github.com/kubernetes-sigs/apiserver-network-proxy |
| containerd | v2.2.3 | Apache-2.0 | https://github.com/containerd/containerd |
| runc | v1.4.2 | Apache-2.0 | https://github.com/opencontainers/runc |
| CNI plugins | v1.9.1 | Apache-2.0 | https://github.com/containernetworking/plugins |
| pause image | registry.k8s.io/pause:3.10.2 | Apache-2.0 | https://github.com/kubernetes/kubernetes (build/pause) |

| Component | Version | License | Source |
|---|---|---|---|
| kube-router | v2.12.0 | Apache-2.0 | https://github.com/cloudnativelabs/kube-router |
| gVisor (runsc, containerd-shim-runsc-v1; the `gvisor` set) | release-20261109.0 | Apache-2.0 | https://github.com/google/gvisor |

## Container images (the `images` set, when an asset build has it)

| Image | License | Source |
|---|---|---|
| ghcr.io/flannel-io/flannel:v0.28.10 | Apache-2.0 | https://github.com/flannel-io/flannel |
| ghcr.io/flannel-io/flannel-cni-plugin:v1.9.1-flannel3 | Apache-2.0 | https://github.com/flannel-io/cni-plugin |
| docker.io/coredns/coredns:1.14.2 | Apache-2.0 | https://github.com/coredns/coredns |
| registry.k8s.io/kube-proxy:v1.36.6 | Apache-2.0 | https://github.com/kubernetes/kubernetes |

Each image also holds its own base layers with their licenses. A
release without the `images` set holds none of these: the nodes pull
them from their registries.

## Debian 13 (trixie) packages in the guest root (`base.img`)

Binary packages from https://deb.debian.org/debian, at the versions in
`scripts/guest/debs.lock` (the packages that file locks; the build takes
the files the guest needs from each). Each package holds its full
copyright and license text in `usr/share/doc/<package>/copyright`. The
build leaves `usr/share/doc` out of the guest to keep it small, so read
it in the package, which the `guest-inputs` release keeps.

| Source package | Binary packages | License |
|---|---|---|
| glibc | libc6, libc-bin | LGPL-2.1-or-later (parts GPL-2.0-or-later) |
| iptables | iptables, libxtables12, libip4tc2, libip6tc2 | GPL-2.0-or-later |
| libnftnl | libnftnl11 | GPL-2.0-or-later |
| libmnl | libmnl0 | LGPL-2.1-or-later |
| libnetfilter-conntrack | libnetfilter-conntrack3 | GPL-2.0-or-later |
| libnfnetlink | libnfnetlink0 | GPL-2.0 |
| conntrack-tools | conntrack | GPL-2.0-or-later |
| ipset | ipset, libipset13t64 | GPL-2.0-only |
| iproute2 | iproute2 | GPL-2.0-or-later |
| busybox | busybox-static | GPL-2.0-only |
| cpio | cpio | GPL-3.0-or-later |
| elfutils | libelf1t64 | LGPL-3.0-or-later or GPL-2.0-or-later |
| libbpf | libbpf1 | LGPL-2.1-only or BSD-2-Clause |
| libcap2 | libcap2 | BSD-3-Clause or GPL-2.0-only |
| libzstd | libzstd1 | BSD-3-Clause or GPL-2.0-only |
| openssl | libssl3t64 | Apache-2.0 |
| zlib | zlib1g | Zlib |
| pcre2 | libpcre2-8-0 | BSD-3-Clause |
| libbsd | libbsd0 | BSD-3-Clause and other BSD licenses |
| libmd | libmd0 | BSD-3-Clause, BSD-2-Clause, ISC, public domain |
| libselinux | libselinux1 | public domain |

## CA certificates

Mozilla's CA root certificates as curl publishes them
(https://curl.se/docs/caextract.html), MPL-2.0.

## Source for the GPL and LGPL programs

- Linux kernel: the kernel.org tarball and patch named above, with the
  config and the build steps in `scripts/guest/kernel.sh` at the commit
  the release was built from.
- BusyBox: busybox.net's tarball of the version in the package, with
  `main/busybox` of Alpine's aports at the commit in the package's
  `.PKGINFO`. The package is in the `guest-inputs` release.
- Debian packages: Debian's source package of the same version at
  `https://snapshot.debian.org/package/<source package>/<version>/` (the
  `.dsc`, the `.orig.tar.*` and the `.debian.tar.*`). The version is the
  one in `scripts/guest/debs.lock`, without a trailing `+b<n>`.

Write to the repository's issue tracker
(https://github.com/chenhunghan/bend-vk8s/issues) if a source named here
is no longer served; the maintainer will provide it.
