import Base
import ../src/cli/extras.bend as X
import ../src/guest/extras.bend as G
import ../src/guest/plan.bend as P

# Spec for src/cli/extras.bend and src/guest/extras.bend: a VM node's
# extras for a host-integrated workload (vk8s create --mount,
# --host-socket, --node-setup).

# Proposed: vk8s design (the brief of 2026-11-25), not vcluster's:
# vcluster has no VM. The expected values come from the documented
# behaviour of what the extras drive:
#   - bend-vmm's README: "--share DIR[,quota=SIZE][,inodes=N][,tag=NAME]
#     [,ro][,meta] ... repeatable (up to 8), each share its own device
#     mounted by its tag"; "ro makes it read-only"; "--vsock PATH ...
#     Firecracker's convention: the guest's connection to host port P
#     reaches PATH_P".
#   - the Linux kernel's Documentation/filesystems/9p.rst: mount -t 9p
#     with trans=virtio, version=9p2000.L, msize=<bytes>; mount(8): ro.
#   - containerd's docs/man/containerd-config.toml.5.md: "imports": a
#     top-level list of paths, globs allowed; docs/cri/config.md: a
#     runtime of runtime_type io.containerd.NAME.v2 is the binary
#     containerd-shim-NAME-v2 on containerd's PATH.
#   - TOML v1.0.0, "Table": a key after a table header belongs to that
#     table, so a top-level key comes before the first header.
#   - cluster.env's own KEY=value lines (src/cli/ctr.bend Ctr.setting).

# --- The flags

# cobra's forms of a string flag: --flag VALUE and --flag=VALUE. Only a
# create has them, and only before "--".
law extras.has_flag:
  {[X.Extras.has_flag(["vk8s", "create", "demo", "--mount", "/Users/u"]), X.Extras.has_flag(["vk8s", "create", "demo", "--node-setup=/Users/u/s.sh"]),
    X.Extras.has_flag(["vk8s", "create", "demo", "--nodes", "1"]), X.Extras.has_flag(["vk8s", "delete", "demo", "--mount", "/Users/u"]),
    X.Extras.has_flag(["vk8s", "create", "demo", "--", "--mount", "/Users/u"])]
   == [True{}, True{}, False{}, False{}, False{}] : List<&2, Bool>}

law extras.drop:
  {X.Extras.drop(["vk8s", "create", "demo", "--mount", "/Users/u", "--nodes", "1", "--host-socket=/run/x.sock=/Users/u/x.sock", "--node-setup", "/Users/u/s.sh"])
   == ["vk8s", "create", "demo", "--nodes", "1"] : +List<String>}

law extras.drop_after_dash:
  {X.Extras.drop(["vk8s", "connect", "demo", "--", "x", "--mount", "/a"]) == ["vk8s", "connect", "demo", "--", "x", "--mount", "/a"] : +List<String>}

# The record of the flags (VK8S_NODE_EXTRAS, and cluster.env's lines): a
# mount is read-only unless :rw, a path may hold spaces, a host socket's
# value is cut at its first "=".
law extras.setting:
  {X.Extras.setting(["vk8s", "create", "demo", "--mount", "/Users/u", "--mount=/Users/u/work dir:rw", "--host-socket",
     "/run/user/502/x.sock=/Users/u/Library/Application Support/app/x.sock", "--node-setup", "/Users/u/setup.sh"])
   == "MOUNT_0=ro:/Users/u\nMOUNT_1=rw:/Users/u/work dir\nHOST_SOCKET_0=/run/user/502/x.sock=/Users/u/Library/Application Support/app/x.sock\nNODE_SETUP=/Users/u/setup.sh\n" : String}

law extras.setting.ro_suffix:
  {X.Extras.setting(["vk8s", "create", "demo", "--mount", "/Users/u/:ro"]) == "MOUNT_0=ro:/Users/u\n" : String}

# The value none names nothing of its kind, and says so.
law extras.setting.none:
  {X.Extras.setting(["vk8s", "create", "demo", "--mount", "none", "--node-setup=none"]) == "MOUNT_NONE=\nNODE_SETUP=\n" : String}

law extras.check.ok:
  {X.Extras.check(["vk8s", "create", "demo", "--mount", "/Users/u", "--mount=/Users/u/work dir:rw", "--host-socket",
     "/run/user/502/x.sock=/Users/u/Library/Application Support/app/x.sock", "--node-setup", "/Users/u/setup.sh"]) == "" : String}

# bend-vmm splits --share's value at commas, and the record is one line
# per mount: such a path is refused, as a relative one is.
law extras.check.refused:
  {[String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/a,b"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/a\nb"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "work"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/Users/../etc"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--host-socket", "/run/x.sock"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--host-socket", "/run/x.sock=x.sock"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--node-setup", "setup.sh"]))]
   == [False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}] : List<&2, Bool>}

# The node mounts a share at the host's path: one of the node's own
# directories, inside one or above one is refused; /var/folders (macOS's
# temporary files) is none of them.
law extras.check.reserved:
  {[String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/etc"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/usr/local"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/var"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/var/lib/vcluster"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/var/folders/x"])), String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount", "/Users/u"]))]
   == [False{}, False{}, False{}, False{}, True{}, True{}] : List<&2, Bool>}

# bend-vmm gives a VM 8 shares; the cluster's share and the layer store
# use two, so a cluster has at most 6 mounts.
law extras.max_mounts:
  {X.Extras.max_mounts() == 6n : Nat}

law extras.check.six_mounts:
  {[String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/b", "--mount=/c", "--mount=/d", "--mount=/e", "--mount=/f"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/b", "--mount=/c", "--mount=/d", "--mount=/e", "--mount=/f", "--mount=/g"]))]
   == [True{}, False{}] : List<&2, Bool>}

law extras.check.twice:
  {[String.is_empty(X.Extras.check(["vk8s", "create", "a", "--mount=/a", "--mount=/a:rw"])),
    String.is_empty(X.Extras.check(["vk8s", "create", "a", "--host-socket=/run/x=/h/a", "--host-socket=/run/x=/h/b"]))]
   == [False{}, False{}] : List<&2, Bool>}

# --- The record

law extras.env_name:
  {X.Extras.env_name() == "VK8S_NODE_EXTRAS" : String}

# A kind the setting names replaces the record's; the others stay.
law extras.merge.kind:
  {X.Extras.env_lines(X.Extras.merge("MOUNT_0=ro:/b\n", "NAME=a\nMOUNT_0=rw:/a\nHOST_SOCKET_0=/g=/h\nNODE_SETUP=/a/s.sh\n"))
   == "MOUNT_0=ro:/b\nHOST_SOCKET_0=/g=/h\nNODE_SETUP=/a/s.sh\n" : String}

law extras.merge.none:
  {X.Extras.env_lines(X.Extras.merge("MOUNT_NONE=\nNODE_SETUP=\n", "MOUNT_0=rw:/a\nHOST_SOCKET_0=/g=/h\nNODE_SETUP=/a/s.sh\n")) == "HOST_SOCKET_0=/g=/h\n" : String}

# Without a setting (create --upgrade with no flag, node add, restore)
# the record stays.
law extras.merge.record:
  {X.Extras.env_lines(X.Extras.merge("", "NAME=a\nMOUNT_0=rw:/a b\nHOST_SOCKET_0=/g=/h =x\nNODE_SETUP=/a/s.sh\nGVISOR=1\n"))
   == "MOUNT_0=rw:/a b\nHOST_SOCKET_0=/g=/h =x\nNODE_SETUP=/a/s.sh\n" : String}

law extras.with_record:
  {[X.Extras.with_record("NAME=a\nMOUNT_0=rw:/old\nPORT=1\nNODE_SETUP=/old.sh\n", X.Extras.of_env("MOUNT_0=ro:/new\n")), X.Extras.with_record("NAME=a\nMOUNT_0=rw:/old\n", X.Extras.none())]
   == ["NAME=a\nPORT=1\nMOUNT_0=ro:/new\n", "NAME=a\n"] : +List<String>}

law extras.keep:
  {[X.Extras.keep("NAME=a\nMOUNT_0=rw:/a b\nGVISOR=1\n"), X.Extras.keep("NAME=a\nGVISOR=1\n")] == ["MOUNT_0=rw:/a b\n", ""] : +List<String>}

# --- A VM's flags, links and share file

# One more --share per mount, read-only unless rw, each with its own tag;
# --vsock at the VM's directory when the cluster has host sockets.
law extras.vmm_flags:
  {X.Extras.vmm_flags(X.Extras.of_env("MOUNT_0=ro:/Users/u\nMOUNT_1=rw:/Users/u/work dir\nHOST_SOCKET_0=/run/x.sock=/Users/u/x.sock\n"), "/h/.vk8s/clusters/demo",
     ["--mem", "2048", "--share", "/h/.vk8s/clusters/demo/share,quota=4G"])
   == ["--mem", "2048", "--share", "/h/.vk8s/clusters/demo/share,quota=4G", "--share", "/Users/u,tag=m0,ro", "--share", "/Users/u/work dir,tag=m1",
       "--vsock", "/h/.vk8s/clusters/demo/vsock"] : +List<String>}

law extras.vmm_flags.no_sockets:
  {X.Extras.vmm_flags(X.Extras.of_env("MOUNT_0=rw:/Users/u\n"), "/h/c/demo", ["--mem", "2048"]) == ["--mem", "2048", "--share", "/Users/u,tag=m0"] : +List<String>}

# A cluster without extras starts its VMs as before.
law extras.vmm_flags.none:
  for +vmdir: String
  for flags: +List<String>
  {X.Extras.vmm_flags(X.Extras.none(), vmdir, flags) == flags : +List<String>}

# Nested mounts: by path length, so a directory comes before any
# directory inside it, whatever the order of the flags.
law extras.sorted.nested:
  {X.Extras.share_text(X.Extras.of_env("MOUNT_0=rw:/Users/u/work\nMOUNT_1=ro:/Users/u\n")) == "mount m0 ro /Users/u\nmount m1 rw /Users/u/work\n" : String}

# bend-vmm sends the guest's connection to host port P to <vsock>_P: that
# path is a link to the host's socket (ports from 100).
law extras.links:
  {X.Extras.links(X.Extras.of_env("HOST_SOCKET_0=/run/a.sock=/Users/u/Library/Application Support/a.sock\nHOST_SOCKET_1=/run/b.sock=/tmp/b.sock\n"), "/h/c/demo")
   == [X.Link{"/h/c/demo/vsock_100", "/Users/u/Library/Application Support/a.sock"}, X.Link{"/h/c/demo/vsock_101", "/tmp/b.sock"}] : +List<X.Link>}

# The node's share file: never the kernel command line (paths may hold
# spaces).
law extras.share_text:
  {X.Extras.share_text(X.Extras.of_env("MOUNT_0=ro:/Users/u\nMOUNT_1=rw:/Users/u/work dir\nHOST_SOCKET_0=/run/user/502/x.sock=/Users/u/Library/Application Support/x.sock\nNODE_SETUP=/Users/u/setup.sh\n"))
   == "mount m0 ro /Users/u\nmount m1 rw /Users/u/work dir\nsocket 100 /run/user/502/x.sock\nsetup /Users/u/setup.sh\n" : String}

law extras.share_file:
  {[X.Extras.share_file(), X.Extras.exit_file()] == [G.Extras.file(), "node-setup.exit"] : +List<String>}

# --- The node

law extras.parse:
  {G.Extras.parse("mount m0 ro /Users/u\nmount m1 rw /Users/u/work dir\nsocket 100 /run/user/502/x.sock\nsetup /Users/u/setup.sh\n")
   == G.Extras{[G.Mnt{"m0", False{}, "/Users/u"}, G.Mnt{"m1", True{}, "/Users/u/work dir"}], [G.Sock{100, "/run/user/502/x.sock"}], "/Users/u/setup.sh"} : G.Extras}

law extras.parse.none:
  {[G.Extras.parse(""), G.Extras.parse("mount m0 wo /a\nsocket x /b\nsetup rel\nother\n")] == [G.Extras.none(), G.Extras.none()] : +List<G.Extras>}

# 9p over virtio at the host's own path, read-only where the share is.
law extras.mount_steps:
  {G.Extras.mount_steps([G.Mnt{"m0", False{}, "/Users/u"}, G.Mnt{"m1", True{}, "/Users/u/work dir"}])
   == [P.Mount{"9p", "m0", "/Users/u", "trans=virtio,version=9p2000.L,msize=524288,ro"},
       P.Mount{"9p", "m1", "/Users/u/work dir", "trans=virtio,version=9p2000.L,msize=524288"}] : +List<P.Step>}

# The proxy: the guest binary's host-sockets mode, PATH PORT per socket,
# as a supervised daemon.
law extras.sock_daemon:
  {List.get(&2, P.Step, G.Extras.sock_steps([G.Sock{100, "/run/user/502/x.sock"}, G.Sock{101, "/run/b.sock"}]), 1n)
   == Some{P.Daemon{"host-sockets", "/sbin/vk8s-init", ["host-sockets", "/run/user/502/x.sock", "100", "/run/b.sock", "101"]}} : Maybe<&2, P.Step>}

law extras.sock_steps.none:
  {G.Extras.sock_steps([]) == [] : +List<P.Step>}

# The script runs under /bin/sh with its path as $1; no script, no step.
law extras.setup_steps:
  {[G.Extras.setup_steps("/Users/u/my setup.sh"), G.Extras.setup_steps("")]
   == [[P.Run{"/bin/busybox", ["sh", "-c", G.Extras.setup_cmd(), "sh", "/Users/u/my setup.sh"]}], []] : +List<+List<P.Step>>}

# The command never fails the boot: it ends with exit 0, after the
# script's exit code went to the share.
law extras.setup_cmd.soft:
  {[String.ends_with(G.Extras.setup_cmd(), "; exit 0"), String.contains(G.Extras.setup_cmd(), "/bin/sh \"$1\" >>/var/lib/vk8s-host/logs/node-setup.log 2>&1"),
    String.contains(G.Extras.setup_cmd(), "echo \"$rc\" >/var/lib/vk8s-host/node-setup.exit")]
   == [True{}, True{}, True{}] : List<&2, Bool>}

# containerd finds containerd-shim-NAME-v2 on its PATH: /usr/local/bin
# comes first.
law extras.env_path:
  {G.Extras.env_path() == "/usr/local/bin:/var/lib/vcluster/bin:/var/lib/vcluster/bin/cni/bin:/usr/sbin:/usr/bin:/sbin:/bin" : String}

# imports is a top-level key: it comes before the first table.
law extras.with_imports:
  {G.Extras.with_imports("version = 3\nroot = \"/var/lib/vcluster/containerd\"\n[grpc]\n  address = \"/run/containerd/containerd.sock\"\n[plugins.'io.containerd.cri.v1.images']\n")
   == "version = 3\nroot = \"/var/lib/vcluster/containerd\"\nimports = [\"/etc/containerd/conf.d/*.toml\"]\n[grpc]\n  address = \"/run/containerd/containerd.sock\"\n[plugins.'io.containerd.cri.v1.images']\n" : String}

law extras.with_imports.once:
  for +text: String
  {G.Extras.with_imports.go(True{}, text) == text : String}

# The steps go before containerd starts, mounts first, then the sockets,
# then the script; with a script, containerd's config imports the
# drop-in directory.
law extras.apply:
  {G.Extras.apply(G.Extras{[G.Mnt{"m0", False{}, "/Users/u"}], [], "/Users/u/s.sh"},
     [P.Write{"/etc/containerd/config.toml", "version = 3\n[grpc]\n"}, P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]},
      P.Daemon{"kubelet", "/var/lib/vcluster/bin/kubelet", []}])
   == [P.Write{"/etc/containerd/config.toml", "version = 3\nimports = [\"/etc/containerd/conf.d/*.toml\"]\n[grpc]\n"},
       P.Mount{"9p", "m0", "/Users/u", "trans=virtio,version=9p2000.L,msize=524288,ro"},
       P.Run{"/bin/busybox", ["sh", "-c", G.Extras.setup_cmd(), "sh", "/Users/u/s.sh"]},
       P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", ["--config", "/etc/containerd/config.toml"]},
       P.Daemon{"kubelet", "/var/lib/vcluster/bin/kubelet", []}] : +List<P.Step>}

# Without a script the config stays as it is.
law extras.apply.no_script:
  {G.Extras.apply(G.Extras{[G.Mnt{"m0", True{}, "/Users/u"}], [], ""},
     [P.Write{"/etc/containerd/config.toml", "version = 3\n[grpc]\n"}, P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", []}])
   == [P.Write{"/etc/containerd/config.toml", "version = 3\n[grpc]\n"}, P.Mount{"9p", "m0", "/Users/u", "trans=virtio,version=9p2000.L,msize=524288"},
       P.Daemon{"containerd", "/var/lib/vcluster/bin/containerd", []}] : +List<P.Step>}

# A node without extras keeps its plan, whatever it is.
law extras.apply.none:
  for steps: +List<P.Step>
  {G.Extras.apply(G.Extras.none(), steps) == steps : +List<P.Step>}
