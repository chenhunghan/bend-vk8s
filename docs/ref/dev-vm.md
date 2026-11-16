# The Linux dev VM on the Mac

A Debian trixie arm64 VM with systemd, booted by vk8s's embedded bend-vmm.
Use it to run `vk8s-linux-arm64` on a Mac: container mode, native mode and
gVisor need only a Linux kernel (docs/GOAL.md section 8, "Testing"). The
KVM backend does not run in it: the M2 cannot nest virtualization.

This is phase 8 of docs/ref/explore-linux-hosts.md, with option b of D14:
the Alpine `linux-virt` kernel that the guest assets use, a stage-0-style
initramfs, and a debootstrap root on `/dev/vda` (finding 7: `debs.py` has
no dependency resolver, so a systemd root needs debootstrap).

## Files

| File | What |
|---|---|
| `scripts/dev/rootfs.sh` | Builds `Image`, `dev.cpio`, `rootfs.img`, `KERNEL` and `SHA256SUMS` on Linux arm64 (needs sudo). |
| `scripts/dev/init` | Stage 0 in `dev.cpio`: loads `virtio_mmio`, `virtio_blk` and `ext4`, mounts `/dev/vda` and runs `switch_root` to systemd. |
| `scripts/dev/linux-vm.sh` | Fetches or takes the image, checks it, boots it with `vk8s vmm` and prints the ssh command. |
| `tests/dev_vm_boot.sh` | Boots the image under `qemu-system-aarch64 -M virt -cpu max` and checks systemd, sshd, sudo, modules, the share and the root size over ssh. |
| `tests/dev_vm_flags.sh` | Checks the `vk8s vmm` flags of `linux-vm.sh` with a fake vk8s. |

The CI job `dev-vm` (on `ubuntu-24.04-arm`) builds the image and boots it.
It publishes the `dev-vm` artifact only when the boot test passes. GitHub
keeps the artifact for 90 days.

## The image

- **Kernel:** Alpine's `linux-virt` for aarch64 from `latest-stable`.
  `scripts/guest/build.sh` gets it the same way. `KERNEL` records the
  `.apk` name and its SHA-256. With `KERNEL_DIR=out/build/kernel16k`,
  `rootfs.sh` uses the 16 KiB-page kernel instead.
- **Root:** `debootstrap --variant=minbase` of trixie with systemd, udev,
  dbus, iproute2, iptables, nftables, conntrack, kmod, curl,
  ca-certificates, openssh-server, sudo, busybox-static, procps,
  iputils-ping and less. The kernel's modules are in
  `/usr/lib/modules/<version>`, uncompressed, with a fresh `depmod`.
- **Network:** `eth0` is 10.0.2.15/24, with the gateway 10.0.2.2 and the
  resolver 10.0.2.3. This is bend-vmm's user-mode NAT, and qemu's
  `-netdev user` gives the same (systemd-networkd).
- **User:** `dev`, with passwordless sudo and no password. Only ssh keys
  can log in. Root cannot log in.
- **ssh key hook:** `devvm.ssh_key=<base64 of an authorized_keys line>`
  on the kernel command line goes into `~dev/.ssh/authorized_keys` on
  each boot (`devvm-ssh-key.service`). Each copy makes its own host keys
  on its first boot.
- **Share:** the 9p share (bend-vmm always tags it `share`) mounts at
  `/repo` on first access (`x-systemd.automount`). A VM without a share
  does not fail a unit.
- **Disk:** `rootfs.img` is 3 GiB. `linux-vm.sh` copies it once to its
  state directory and makes the copy larger (`DEV_VM_DISK`, 32G). systemd
  grows the file system to the disk on boot (`x-systemd.growfs`).

## Use it on the Mac

You need a `vk8s` binary (a release, or `scripts/build-mac.sh`) and `gh`
logged in to GitHub to fetch the artifact.

```sh
scripts/dev/linux-vm.sh            # fetch, check, boot; prints the ssh command
scripts/dev/linux-vm.sh ssh        # log in as dev
scripts/dev/linux-vm.sh stop       # power button, then quit
```

The VM gets `--mem 4096 --cpus 4`, the repository at `/repo` (a share
quota of 8G), and its sshd on `127.0.0.1:2222`. To use files you built
or downloaded, give their directory: `linux-vm.sh up --dir DIR`. DIR holds
`Image`, `dev.cpio` and `rootfs.img`. When DIR has a `SHA256SUMS`, the
script checks the files against it. `--dry-run` prints the `vk8s vmm`
words and does not start the VM. The state (disk, key, logs, console) is
in `~/.vk8s/dev-vm`. Delete `disk.img` there to get a fresh root.

To test a Linux build of vk8s (the `--backend` flag comes with phases 5
and 6 of the explorer plan):

```sh
# on the Mac: put vk8s-linux-arm64 in the repository (the share)
scripts/dev/linux-vm.sh ssh
# in the VM
cd /repo
sudo modprobe -a overlay br_netfilter nf_tables   # the modules are there
./vk8s-linux-arm64 create demo --backend native    # native: systemd units, sudo for root steps
./vk8s-linux-arm64 create demo2 --backend container
```

The VM runs systemd with cgroup v2, so native mode (a systemd unit per
cluster) and container mode (a delegated cgroup v2 subtree) have what
they need. For gVisor, put `runsc` and its shim in `/repo`. The systrap
platform needs no nested virtualization (finding 6).

## Pinning

`scripts/dev/linux-vm.sh` has two pins at its top: `PIN_RUN` and
`PIN_SUMS`.

1. Wait for a green `check` run on `main` with the `dev-vm` job.
2. Copy the run ID from its URL (`.../actions/runs/<ID>`), and the
   `SHA256SUMS` lines that the step "The image" printed.
3. Set `PIN_RUN=<ID>` and `PIN_SUMS='<the three lines>'`, and commit.

`linux-vm.sh` then fetches that run's artifact and refuses a file whose
SHA-256 is different. With no pin, it takes the newest green run on
`main`. It checks the files against that artifact's own `SHA256SUMS` and
prints the pin lines. `--run ID` (or `DEV_VM_RUN`) picks another run.

Each build makes a different `rootfs.img`, because `mkfs.ext4` writes a
new UUID and new times. Pin the run, not a rebuild. An artifact expires
after 90 days. Before that, pin a newer run or attach the files to a
release.

## Limits

- The Alpine kernel is `latest-stable`, not pinned, as in
  `scripts/guest/build.sh`. `KERNEL` in the artifact names the package
  that each image used.
- No KVM in the VM on an M2. Test the `vm` backend on a Linux KVM host
  (docs/GOAL.md section 8).
- Not verified: a boot under bend-vmm on a Mac. CI boots the image under
  qemu only, with the same console, disk, network and share devices.
