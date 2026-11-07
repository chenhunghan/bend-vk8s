import Base

# vcluster's certificate management in standalone mode (vcluster
# pkg/certs, a8ab30e), as pure decisions. The host (host/) runs the steps:
# it makes keys and certificates (kubeadm's library or openssl), reads the
# PEM files and the clock, and restarts the control plane.
#
# - Certs.plan: the certificates kubeadm's CreatePKIAssets makes
#   (GetDefaultCertList, local etcd), with their CN, organizations, signing
#   CA, extended key usages, SANs and validity, as kubeadm's CertConfig holds
#   them before signing. Certs.final_dns and Certs.final_ips are the SANs
#   the signed certificate carries (pkiutil.RemoveDuplicateAltNames).
# - Certs.kubeconfigs: the kubeconfigs of the PKI directory.
# - Certs.files: the file layout under /var/lib/vcluster/pki (certMap).
# - Certs.needs_renewal: the renewal rule (certhelper.IsCertExpired).
# - Certs.secret_expiring, Certs.disk_expiring: whether a leaf certificate
#   needs renewal (certsExpiringSoon, diskCertsExpiringSoon).
# - Certs.ensure_steps, Certs.rotation_steps, Certs.watcher_steps: what
#   EnsureCerts (startup), Rotate (`certs rotate`, `certs rotate-ca`) and
#   the cert watcher do, as ordered steps.
#
# Time is in whole hours since the Unix epoch (Nat). vcluster compares
# float hours: (NotAfter - now).Hours() / 24 <= 90. The host passes
# NotAfter rounded down and now rounded up, so vk8s renews no later than
# vcluster, and at most 2 hours earlier.
#
# vcluster quirks kept as they are:
# - A missing, empty or unreadable leaf certificate counts as expiring; a
#   CA certificate never triggers renewal (it only warns).
# - Leaf removal keeps every file whose base name is ca.crt or ca.key or
#   ends in -ca.crt or -ca.key, so etcd/ca.* and the server-ca and
#   client-ca copies stay; sa.key and sa.pub always stay. Every other file
#   in the PKI directory goes, the three kubeconfigs too.
# - generateCertificates writes admin.conf for kubernetes-admin, then
#   writes super-admin.conf and renames it over admin.conf: admin.conf is
#   the super-admin kubeconfig (system:masters).
# - server-ca and client-ca are copies of ca, made only when missing
#   (copyFileIfNotExists): a rotation of the CA (rotate-ca) removes them
#   first, so they are copied from the new CA.
# - Rotation in standalone mode removes etcd/{peer,server}.{crt,key} after
#   it regenerated them; they are made again when etcd starts.
# - Startup renewal (EnsureCerts) neither backs up the PKI directory nor
#   removes the etcd server and peer certificates.
# - The CA warning names `vcluster certs rotate-ca`, as vcluster does.

# The kubeadm configuration vcluster builds (pkg/kubeadm/config.go):
# name is NodeRegistration.Name and the cluster name (standalone); adv the
# LocalAPIEndpoint advertise address; ep the host of ControlPlaneEndpoint
# ("" for none); vip the first IP of the service CIDR
# (GetAPIServerVirtualIP); domain the DNS domain; api_sans the
# APIServer.CertSANs; etcd_sans the etcd server and peer extra SANs
# (Certs.etcd_extra_sans).
type Cfg is Data:
  Cfg{name: String, adv: String, ep: String, vip: String, domain: String, api_sans: +List<String>, etcd_sans: +List<String>}

# x509 extended key usages.
type Usage is Data:
  ServerAuth{}
  ClientAuth{}

# A certificate as kubeadm configures it: base is the file name under the
# PKI directory without .crt/.key; ca the base of the signing CA ("" for a
# self-signed CA); days the validity.
type Spec is Data:
  Spec{base: String, cn: String, orgs: +List<String>, ca: String, usages: +List<Usage>, dns: +List<String>, ips: +List<String>, days: Nat}

# A kubeconfig with a client certificate signed by ca: file under the PKI
# directory, the client's CN (user) and organizations, the API server URL,
# the cluster name, the client certificate's validity.
type Kconf is Data:
  Kconf{file: String, user: String, orgs: +List<String>, server: String, cluster: String, days: Nat}

# One certificate of a PEM file: its CN and NotAfter (hours).
type Cert is Data:
  Cert{cn: String, not_after: Nat}

# What a certificate file or secret entry holds: nothing (missing or
# empty), something that is no PEM certificate, or certificates.
type Pem is Data:
  Absent{}
  Unparsable{}
  Bundle{certs: +List<Cert>}

# A secret entry or a file: its key or path, and its contents.
type Entry is Data:
  Entry{key: String, pem: Pem}

# What the host does, in order. Paths are absolute.
type Step is Data:
  # copy the directory tree src to dst (backupPKI)
  Backup{src: String, dst: String}
  # remove every file under dir except those Certs.keep(base name, keep_ca)
  # keeps (removeFiles with excludeSAFiles, and excludeCAFiles if keep_ca)
  RemoveFiles{dir: String, keep_ca: Bool}
  # remove a file; a missing file is no error
  Remove{path: String}
  # create the certificate and key of spec, unless they exist
  CreateCert{spec: Spec}
  # create sa.key and sa.pub, unless sa.key exists
  CreateSAKeys{}
  # create the kubeconfig, unless it exists
  CreateKubeconfig{kc: Kconf}
  Rename{src: String, dst: String}
  # write the first PEM block of src to dst, unless dst exists
  CopyCertIfMissing{src: String, dst: String}
  # copy src to dst, unless dst exists
  CopyIfMissing{src: String, dst: String}
  # in every cluster of the kubeconfig at path: certificate-authority ""
  # and certificate-authority-data the contents of ca
  TrustCA{path: String, ca: String}
  # exit after a random delay of min_s to max_s seconds (the restart picks
  # up the new certificates)
  ExitAfter{min_s: U32, max_s: U32}

# A class of characters (Certs.all).
type Cls is Data:
  LabelCh{}
  DigitCh{}
  IpCh{}

# A kubeconfig cluster entry.
type Cluster is Data:
  Cluster{server: String, ca_file: String, ca_data: String}

# A file of a modelled directory.
type PkiFile is Data:
  PkiFile{path: String, data: String}

# The control-plane rollout of clustered mode (finishPendingRollout): a
# merge patch of the pod template annotation key = value.
type Rollout is Data:
  PatchStatefulSet{namespace: String, name: String, key: String, value: String}
  PatchDeployment{namespace: String, name: String, key: String, value: String}
  RolloutError{message: String}
  NoRollout{}

# Constants.

def Certs.data() -> String:
  "/var/lib/vcluster"

# vcluster's PKIDir in standalone mode.
def Certs.pki() -> String:
  "/var/lib/vcluster/pki"

def Certs.p(+f: String) -> String:
  Certs.pki() ++ "/" ++ f

# certhelper.IsCertExpired: 90 days.
def Certs.renew_hours() -> Nat:
  2160n

# DefaultCheckInterval: 24 h.
def Certs.check_interval_s() -> U32:
  86400

# runCertWatcher's jitter: up to interval / 10.
def Certs.jitter_max_s() -> U32:
  8640

# certRotationExitDelayMin and certRotationExitDelayMax.
def Certs.exit_delay_min_s() -> U32:
  5

def Certs.exit_delay_max_s() -> U32:
  300

# certRotationLeaseDuration (HA only).
def Certs.lease_s() -> U32:
  300

# kubeadm CertificateValidityPeriod (leaf certificates and kubeconfig
# client certificates) and CACertificateValidityPeriod, in days.
def Certs.leaf_days() -> Nat:
  365n

def Certs.ca_days() -> Nat:
  3650n

# kubeadm's default EncryptionAlgorithm, RSA-2048.
def Certs.key_bits() -> U32:
  2048

def Certs.rotation_annotation() -> String:
  "vcluster.loft.sh/cert-rotation-at"

# Strings and lists.

def Certs.elem(+k: String, xs: +List<String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{x, r}:
      Bool.or(String.eq(k, x), Certs.elem(k, r))

def Certs.is_digit(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.and(U32.is_le(48, x), U32.is_le(x, 57))

def Certs.is_lower(c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.and(U32.is_le(97, x), U32.is_le(x, 122))

def Certs.is_alnum(+c: Char) -> Bool:
  Bool.or(Certs.is_lower(c), Certs.is_digit(c))

def Certs.is_hex(+c: Char) -> Bool:
  match c:
    case Chr{+x}:
      Bool.or(Certs.is_digit(Chr{x}), Bool.or(Bool.and(U32.is_le(97, x), U32.is_le(x, 102)), Bool.and(U32.is_le(65, x), U32.is_le(x, 70))))

# Every character satisfies the class: LabelCh alnum or '-'; DigitCh a
# digit; IpCh hex, ':' or '.'.
def Certs.all.one(k: Cls, +c: Char) -> Bool:
  match k:
    case LabelCh{}:
      Bool.or(Certs.is_alnum(c), Char.is_eq(c, '-'))
    case DigitCh{}:
      Certs.is_digit(c)
    case IpCh{}:
      Bool.or(Certs.is_hex(c), Bool.or(Char.is_eq(c, ':'), Char.is_eq(c, '.')))

def Certs.all(+k: Cls, s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Bool.and(Certs.all.one(k, h), Certs.all(k, t))

def Certs.alnum_at(m: Maybe<&2, Char>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{c}:
      Certs.is_alnum(c)

# A DNS-1123 label: [a-z0-9]([-a-z0-9]*[a-z0-9])?
def Certs.label_ok(+l: String) -> Bool:
  Bool.and(Certs.all(LabelCh{}, l), Bool.and(Certs.alnum_at(String.get(l, 0n)), Certs.alnum_at(String.get(String.reverse(l), 0n))))

def Certs.labels_ok(ls: List<&2, String>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{h, t}:
      Bool.and(Certs.label_ok(h), Certs.labels_ok(t))

# validation.IsDNS1123Subdomain.
def Certs.is_dns(+s: String) -> Bool:
  Bool.and(Nat.is_le(String.length(s), 253n), Certs.labels_ok(String.split(s, '.')))

# validation.IsWildcardDNS1123Subdomain: "*." and a subdomain.
def Certs.is_wildcard(+s: String) -> Bool:
  Bool.and(String.starts_with(s, "*."), Bool.and(Nat.is_le(String.length(s), 253n), Certs.is_dns(String.drop(s, 2n))))

def Certs.octet_ok(+p: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(p)), Bool.and(Nat.is_le(String.length(p), 3n),
    Bool.and(Certs.all(DigitCh{}, p), U32.is_le(Maybe.default(&2, U32, U32.read(p), 256), 255))))

def Certs.octets_ok(ps: List<&2, String>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{+h, t}:
      Bool.and(Certs.octet_ok(h), Certs.octets_ok(t))

# netutils.ParseIPSloppy accepts it: a dotted IPv4 address (leading zeros
# allowed) or an IPv6 address (hex digits, ':' and '.', with a ':').
def Certs.is_ip(+s: String) -> Bool:
  Bool.or(
    Bool.and(Nat.is_eq(List.length(&2, String, String.split(s, '.')), 4n), Certs.octets_ok(String.split(s, '.'))),
    Bool.and(String.contains(s, ":"), Certs.all(IpCh{}, s)))

def Certs.pick.if(keep: Bool, +s: String, rest: +List<String>) -> +List<String>:
  match keep:
    case True{}:
      s <> rest
    case False{}:
      rest

# appendSANsToAltNames: the IPs, and the DNS names and wildcards, of a SAN
# list; anything else is left out.
def Certs.san_ips(sans: +List<String>) -> +List<String>:
  match sans:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Certs.pick.if(Certs.is_ip(s), s, Certs.san_ips(t))

def Certs.san_dns(sans: +List<String>) -> +List<String>:
  match sans:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Certs.pick.if(Bool.and(Bool.not(Certs.is_ip(s)), Bool.or(Certs.is_dns(s), Certs.is_wildcard(s))), s, Certs.san_dns(t))

def Certs.ins.if(c: Cmp, +x: String, +h: String, t: +List<String>, rec: +List<String>) -> +List<String>:
  match c:
    case LT{}:
      x <> (h <> t)
    case EQ{}:
      h <> t
    case GT{}:
      h <> rec

# x into a sorted list without duplicates.
def Certs.ins(+x: String, xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      [x]
    case Con{+h, +t}:
      Certs.ins.if(String.order(x, h), x, h, t, Certs.ins(x, t))

# sets.List(sets.New(xs...)): sorted, without duplicates.
def Certs.sort_uniq(xs: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Certs.ins(h, Certs.sort_uniq(t))

def Certs.uniq.if(seen: Bool, +h: String, rest: +List<String>) -> +List<String>:
  match seen:
    case True{}:
      rest
    case False{}:
      h <> rest

def Certs.uniq.go(xs: +List<String>, +seen: +List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Certs.uniq.if(Certs.elem(h, seen), h, Certs.uniq.go(t, h <> seen))

# The first of each, in order.
def Certs.uniq(xs: +List<String>) -> +List<String>:
  Certs.uniq.go(xs, [])

# Specs.

def Certs.Spec.base(s: Spec) -> String:
  match s:
    case Spec{b, cn, o, ca, u, d, i, n}:
      b

def Certs.Spec.cn(s: Spec) -> String:
  match s:
    case Spec{b, cn, o, ca, u, d, i, n}:
      cn

def Certs.Spec.dns(s: Spec) -> +List<String>:
  match s:
    case Spec{b, cn, o, ca, u, d, i, n}:
      d

def Certs.Spec.ips(s: Spec) -> +List<String>:
  match s:
    case Spec{b, cn, o, ca, u, d, i, n}:
      i

def Certs.Cfg.name(c: Cfg) -> String:
  match c:
    case Cfg{name, adv, ep, vip, dom, api, etcd}:
      name

# The SANs of the signed certificate: DNS names sorted without
# duplicates, IPs without duplicates (pkiutil.RemoveDuplicateAltNames).
def Certs.final_dns(+s: Spec) -> +List<String>:
  Certs.sort_uniq(Certs.Spec.dns(s))

def Certs.final_ips(+s: Spec) -> +List<String>:
  Certs.uniq(Certs.Spec.ips(s))

# Is the certificate's CN one of its DNS SANs?
def Certs.cn_in_san(+s: Spec) -> Bool:
  Certs.elem(Certs.Spec.cn(s), Certs.Spec.dns(s))

def Certs.cn_in_san_all(ss: +List<Spec>) -> +List<Bool>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{+s, t}:
      Certs.cn_in_san(s) <> Certs.cn_in_san_all(t)

def Certs.leaf(+base: String, +cn: String, +ca: String, +usages: +List<Usage>) -> Spec:
  Spec{base, cn, [], ca, usages, [], [], Certs.leaf_days()}

def Certs.authority(+base: String, +cn: String) -> Spec:
  Spec{base, cn, [], "", [], [], [], Certs.ca_days()}

def Certs.opt.if(empty: Bool, +s: String) -> +List<String>:
  match empty:
    case True{}:
      []
    case False{}:
      [s]

# [s] unless s is "".
def Certs.opt(+s: String) -> +List<String>:
  Certs.opt.if(String.is_empty(s), s)

def Certs.ep.if(want_ip: Bool, is_ip: Bool, +h: String) -> +List<String>:
  match want_ip:
    case True{}:
      Certs.pick.if(is_ip, h, [])
    case False{}:
      Certs.pick.if(Bool.not(is_ip), h, [])

# The controlPlaneEndpoint host goes to the IPs or the DNS names.
def Certs.ep(want_ip: Bool, +h: String) -> +List<String>:
  Certs.ep.if(want_ip, Certs.is_ip(h), h)

def Certs.ep.go(empty: Bool, want_ip: Bool, +h: String) -> +List<String>:
  match empty:
    case True{}:
      []
    case False{}:
      Certs.ep(want_ip, h)

def Certs.ep_san(want_ip: Bool, +h: String) -> +List<String>:
  Certs.ep.go(String.is_empty(h), want_ip, h)

# The CA kubeadm signs everything of the Kubernetes CA with.
def Certs.ca() -> Spec:
  Certs.authority("ca", "kubernetes")

# kubeadm's API server certificate (GetAPIServerAltNames), signed by
# signer ("ca"; "server-ca" when the CAs are split).
def Certs.apiserver(+c: Cfg, +signer: String) -> Spec:
  match c:
    case Cfg{+name, +adv, +ep, +vip, +dom, +api, +etcd}:
      Spec{"apiserver", "kube-apiserver", [], signer, [ServerAuth{}],
        List.concat(&2, String, [Certs.opt(name),
          ["kubernetes", "kubernetes.default", "kubernetes.default.svc"],
          Certs.opt.if(String.is_empty(dom), "kubernetes.default.svc." ++ dom),
          Certs.ep_san(False{}, ep),
          Certs.san_dns(api)]),
        List.concat(&2, String, [[vip, adv], Certs.ep_san(True{}, ep), Certs.san_ips(api)]),
        Certs.leaf_days()}

def Certs.kubelet_client() -> Spec:
  Certs.leaf("apiserver-kubelet-client", "kube-apiserver-kubelet-client", "ca", [ClientAuth{}])

def Certs.front_proxy_ca() -> Spec:
  Certs.authority("front-proxy-ca", "front-proxy-ca")

def Certs.front_proxy_client() -> Spec:
  Certs.leaf("front-proxy-client", "front-proxy-client", "front-proxy-ca", [ClientAuth{}])

def Certs.etcd_ca() -> Spec:
  Certs.authority("etcd/ca", "etcd-ca")

def Certs.node_dns.if(empty: Bool, +name: String) -> +List<String>:
  match empty:
    case True{}:
      ["localhost"]
    case False{}:
      [name, "localhost"]

# getAltNames: the node name (when set) and localhost.
def Certs.node_dns(+name: String) -> +List<String>:
  Certs.node_dns.if(String.is_empty(name), name)

def Certs.etcd_dns(+name: String, +sans: +List<String>) -> +List<String>:
  List.append(&2, String, Certs.node_dns(name), Certs.san_dns(sans))

def Certs.etcd_ips(+adv: String, +sans: +List<String>) -> +List<String>:
  List.append(&2, String, [adv, "127.0.0.1", "::1"], Certs.san_ips(sans))

# etcd's serving certificate: CN the node name (setCommonNameToNodeName).
def Certs.etcd_server(+c: Cfg) -> Spec:
  match c:
    case Cfg{+name, +adv, +ep, +vip, +dom, +api, +etcd}:
      Spec{"etcd/server", name, [], "etcd-ca", [ServerAuth{}, ClientAuth{}], Certs.etcd_dns(name, etcd), Certs.etcd_ips(adv, etcd), Certs.leaf_days()}

def Certs.etcd_peer(+c: Cfg) -> Spec:
  match c:
    case Cfg{+name, +adv, +ep, +vip, +dom, +api, +etcd}:
      Spec{"etcd/peer", name, [], "etcd-ca", [ServerAuth{}, ClientAuth{}], Certs.etcd_dns(name, etcd), Certs.etcd_ips(adv, etcd), Certs.leaf_days()}

def Certs.etcd_healthcheck() -> Spec:
  Certs.leaf("etcd/healthcheck-client", "kube-etcd-healthcheck-client", "etcd-ca", [ClientAuth{}])

def Certs.etcd_client() -> Spec:
  Certs.leaf("apiserver-etcd-client", "kube-apiserver-etcd-client", "etcd-ca", [ClientAuth{}])

# GetEtcdExtraSANs in standalone mode, with controlPlane.proxy.extraSANs.
def Certs.etcd_extra_sans(proxy: +List<String>) -> +List<String>:
  "localhost" <> ("127.0.0.1" <> ("0.0.0.0" <> proxy))

# The configuration vcluster standalone builds (GenerateInitKubeadmConfig):
# advertise address and control-plane endpoint 127.0.0.1, no API server
# extra SANs.
def Certs.vcluster_cfg(+name: String, +vip: String, +domain: String, proxy: +List<String>) -> Cfg:
  Cfg{name, "127.0.0.1", "127.0.0.1", vip, domain, [], Certs.etcd_extra_sans(proxy)}

def Certs.plan.kube(+c: Cfg) -> +List<Spec>:
  [Certs.ca(), Certs.apiserver(c, "ca"), Certs.kubelet_client(), Certs.front_proxy_ca(), Certs.front_proxy_client()]

def Certs.plan.etcd(+c: Cfg) -> +List<Spec>:
  [Certs.etcd_ca(), Certs.etcd_server(c), Certs.etcd_peer(c), Certs.etcd_healthcheck(), Certs.etcd_client()]

# The certificates of kubeadm's GetDefaultCertList, in its order. Both
# halves (Kubernetes and front proxy, etcd) are built in parallel.
def Certs.plan(+c: Cfg) -> +List<Spec>:
  kube etcd = Certs.plan.kube(c) Certs.plan.etcd(c)
  List.append(&2, Spec, kube, etcd)

def Certs.server(+host: String) -> String:
  "https://" ++ host ++ ":6443"

def Certs.ep_host.if(empty: Bool, +ep: String, +adv: String) -> String:
  match empty:
    case True{}:
      adv
    case False{}:
      ep

# GetControlPlaneEndpoint: the endpoint host, else the advertise address.
def Certs.ep_host(+ep: String, +adv: String) -> String:
  Certs.ep_host.if(String.is_empty(ep), ep, adv)

def Certs.kubeconfig.host(local: Bool, +ep: String, +adv: String) -> String:
  match local:
    case True{}:
      adv
    case False{}:
      Certs.ep_host(ep, adv)

# kubeadm's kubeconfig specs (getKubeConfigSpecsBase): admin.conf and
# super-admin.conf use the control-plane endpoint, the controller manager
# and the scheduler the local API endpoint.
def Certs.kubeconfig(+c: Cfg, +file: String, +user: String, +orgs: +List<String>, local: Bool) -> Kconf:
  match c:
    case Cfg{+name, +adv, +ep, +vip, +dom, +api, +etcd}:
      Kconf{file, user, orgs, Certs.server(Certs.kubeconfig.host(local, ep, adv)), name, Certs.leaf_days()}

# The kubeconfigs left in the PKI directory.
def Certs.kubeconfigs(+c: Cfg) -> +List<Kconf>:
  [ Certs.kubeconfig(c, "admin.conf", "kubernetes-super-admin", ["system:masters"], False{}),
    Certs.kubeconfig(c, "controller-manager.conf", "system:kube-controller-manager", [], True{}),
    Certs.kubeconfig(c, "scheduler.conf", "system:kube-scheduler", [], True{}) ]

# kubeadm's context name, user@cluster.
def Certs.context(k: Kconf) -> String:
  match k:
    case Kconf{f, u, o, s, cl, d}:
      u ++ "@" ++ cl

# The kubeconfig files a rotation rewrites: the three of the PKI
# directory (removed with the leaf certificates and made again), and the
# user kubeconfig vcluster writes when it starts again
# (WriteKubeConfigToSecret, standalone: <DataDir>/kubeconfig.yaml).
def Certs.rewritten_kubeconfigs() -> +List<String>:
  [ Certs.p("admin.conf"), Certs.p("controller-manager.conf"), Certs.p("scheduler.conf"),
    Certs.data() ++ "/kubeconfig.yaml" ]

# File layout.

# The files of the PKI directory vcluster tracks (certMap's keys).
def Certs.files() -> +List<String>:
  [ "admin.conf", "controller-manager.conf", "scheduler.conf",
    "apiserver.crt", "apiserver.key",
    "apiserver-etcd-client.crt", "apiserver-etcd-client.key",
    "apiserver-kubelet-client.crt", "apiserver-kubelet-client.key",
    "ca.crt", "ca.key", "server-ca.crt", "server-ca.key", "client-ca.crt", "client-ca.key",
    "front-proxy-ca.crt", "front-proxy-ca.key", "front-proxy-client.crt", "front-proxy-client.key",
    "sa.key", "sa.pub",
    "etcd/ca.crt", "etcd/ca.key",
    "etcd/healthcheck-client.crt", "etcd/healthcheck-client.key",
    "etcd/peer.crt", "etcd/peer.key",
    "etcd/server.crt", "etcd/server.key" ]

def Certs.dash.if(slash: Bool, c: Char) -> Char:
  match slash:
    case True{}:
      '-'
    case False{}:
      c

def Certs.dash(c: Char) -> Char:
  Certs.dash.if(Char.is_eq(c, '/'), c)

# A file's key in the certs secret (certMap: "/" becomes "-").
def Certs.secret_key(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      SCon{Certs.dash(h), Certs.secret_key(t)}

def Certs.secret_keys.go(fs: +List<String>) -> +List<String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, t}:
      Certs.secret_key(f) <> Certs.secret_keys.go(t)

def Certs.secret_keys() -> +List<String>:
  Certs.secret_keys.go(Certs.files())

# isCAFile: a CA certificate's secret key.
def Certs.is_ca_file(+k: String) -> Bool:
  Certs.elem(k, ["ca.crt", "server-ca.crt", "client-ca.crt", "front-proxy-ca.crt", "etcd-ca.crt"])

def Certs.is_leaf_crt(+k: String) -> Bool:
  Bool.and(String.ends_with(k, ".crt"), Bool.not(Certs.is_ca_file(k)))

def Certs.is_ca_crt(+k: String) -> Bool:
  Bool.and(String.ends_with(k, ".crt"), Certs.is_ca_file(k))

# The leaf certificates' secret keys (certsExpiringSoon checks these).
def Certs.leaf_keys.go(ks: +List<String>) -> +List<String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, t}:
      Certs.pick.if(Certs.is_leaf_crt(k), k, Certs.leaf_keys.go(t))

def Certs.leaf_secret_keys() -> +List<String>:
  Certs.leaf_keys.go(Certs.secret_keys())

# The leaf certificates' files (diskCertsExpiringSoon checks these).
def Certs.leaf_files.go(fs: +List<String>) -> +List<String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+f, t}:
      Certs.pick.if(Certs.is_leaf_crt(Certs.secret_key(f)), f, Certs.leaf_files.go(t))

def Certs.leaf_files() -> +List<String>:
  Certs.leaf_files.go(Certs.files())

# The CA certificates' secret keys (warnIfCAExpiring checks these).
def Certs.ca_keys.go(ks: +List<String>) -> +List<String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{+k, t}:
      Certs.pick.if(Certs.is_ca_crt(k), k, Certs.ca_keys.go(t))

def Certs.ca_secret_keys() -> +List<String>:
  Certs.ca_keys.go(Certs.secret_keys())

# excludeSAFiles.
def Certs.is_sa(+name: String) -> Bool:
  Bool.or(String.eq(name, "sa.pub"), String.eq(name, "sa.key"))

# excludeCAFiles (a base name).
def Certs.is_ca(+name: String) -> Bool:
  Bool.or(Bool.or(String.eq(name, "ca.crt"), String.eq(name, "ca.key")),
    Bool.or(String.ends_with(name, "-ca.crt"), String.ends_with(name, "-ca.key")))

# Does removeFiles keep the file with this base name?
def Certs.keep(+name: String, keep_ca: Bool) -> Bool:
  Bool.or(Certs.is_sa(name), Bool.and(keep_ca, Certs.is_ca(name)))

def Certs.last(t: List<&2, String>, h: String) -> String:
  match t:
    case Nil{}:
      h
    case Con{x, r}:
      Certs.last(r, x)

def Certs.basename.go(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{h, t}:
      Certs.last(t, h)

def Certs.basename(s: String) -> String:
  Certs.basename.go(String.split(s, '/'))

# The files (paths under the PKI directory) RemoveFiles removes.
def Certs.removed(fs: +List<String>, +keep_ca: Bool) -> +List<String>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{+f, t}:
      Certs.pick.if(Bool.not(Certs.keep(Certs.basename(f), keep_ca)), f, Certs.removed(t, keep_ca))

# Renewal.

# certhelper.IsCertExpired: the certificate expires within 90 days (or
# has expired).
def Certs.needs_renewal(now: Nat, not_after: Nat) -> Bool:
  Nat.is_le(not_after, Nat.add(now, Certs.renew_hours()))

def Certs.any_expiring(+now: Nat, cs: +List<Cert>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{Cert{cn, na}, t}:
      Bool.or(Certs.needs_renewal(now, na), Certs.any_expiring(now, t))

def Certs.bundle_expiring(+now: Nat, cs: +List<Cert>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{c, t}:
      Certs.any_expiring(now, c <> t)

# A leaf entry needs renewal: missing, empty or unreadable (ParseCertsPEM
# fails, also for no certificate at all), or a certificate within 90 days.
def Certs.pem_expiring(+now: Nat, p: Pem) -> Bool:
  match p:
    case Absent{}:
      True{}
    case Unparsable{}:
      True{}
    case Bundle{cs}:
      Certs.bundle_expiring(now, cs)

def Certs.lookup.if(hit: Bool, p: Pem, rest: Pem) -> Pem:
  match hit:
    case True{}:
      p
    case False{}:
      rest

def Certs.lookup(es: +List<Entry>, +k: String) -> Pem:
  match es:
    case Nil{}:
      Absent{}
    case Con{Entry{key, +p}, t}:
      Certs.lookup.if(String.eq(key, k), p, Certs.lookup(t, k))

def Certs.expiring_in(+now: Nat, ks: +List<String>, +es: +List<Entry>) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{k, t}:
      Bool.or(Certs.pem_expiring(now, Certs.lookup(es, k)), Certs.expiring_in(now, t, es))

# certsExpiringSoon: the certs secret's entries, by secret key.
def Certs.secret_expiring(+now: Nat, +es: +List<Entry>) -> Bool:
  Certs.expiring_in(now, Certs.leaf_secret_keys(), es)

# diskCertsExpiringSoon (checkCertsExpiring): the PKI directory's files, by
# path under it.
def Certs.disk_expiring(+now: Nat, +es: +List<Entry>) -> Bool:
  Certs.expiring_in(now, Certs.leaf_files(), es)

def Certs.ca_cns(+now: Nat, cs: +List<Cert>) -> +List<String>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{Cert{+cn, na}, t}:
      Certs.pick.if(Certs.needs_renewal(now, na), cn, Certs.ca_cns(now, t))

def Certs.ca_pem(+now: Nat, p: Pem) -> +List<String>:
  match p:
    case Bundle{cs}:
      Certs.ca_cns(now, cs)
    case _:
      Nil{}

def Certs.ca_expiring_in(+now: Nat, ks: +List<String>, +es: +List<Entry>) -> +List<String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, t}:
      List.append(&2, String, Certs.ca_pem(now, Certs.lookup(es, k)), Certs.ca_expiring_in(now, t, es))

# warnIfCAExpiring: the CNs of the CA certificates within 90 days (a
# missing, empty or unreadable entry is skipped).
def Certs.ca_expiring(+now: Nat, +es: +List<Entry>) -> +List<String>:
  Certs.ca_expiring_in(now, Certs.ca_secret_keys(), es)

def Certs.ca_warning(+cn: String, +at: String) -> String:
  "CA certificate (CN=" ++ cn ++ ") expires at " ++ at ++ "; run \"vcluster certs rotate-ca\" to renew"

# HasSplitClusterSigningCA, given the first certificate of each file.
def Certs.split_ca(+server: String, +client: String) -> Bool:
  Bool.not(String.eq(server, client))

# ensureKubeConfigTrustsCA on one cluster.
def Certs.trust_ca(c: Cluster, +data: String) -> Cluster:
  match c:
    case Cluster{s, f, d}:
      Cluster{s, "", data}

# Steps.

def Certs.create_certs(ss: +List<Spec>) -> +List<Step>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      CreateCert{s} <> Certs.create_certs(t)

def Certs.create_kubeconfigs(ks: +List<Kconf>) -> +List<Step>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, t}:
      CreateKubeconfig{k} <> Certs.create_kubeconfigs(t)

# splitCACert: server-ca and client-ca from ca, when missing.
def Certs.split_ca_steps() -> +List<Step>:
  [ CopyCertIfMissing{Certs.p("ca.crt"), Certs.p("server-ca.crt")},
    CopyIfMissing{Certs.p("ca.key"), Certs.p("server-ca.key")},
    CopyCertIfMissing{Certs.p("ca.crt"), Certs.p("client-ca.crt")},
    CopyIfMissing{Certs.p("ca.key"), Certs.p("client-ca.key")} ]

# ensureAPIServerServingCertSignedByServerCA: with split CAs (ca.crt and
# server-ca.crt differ), the API server certificate is made again, signed
# by server-ca.
def Certs.serving_steps(+c: Cfg, split: Bool) -> +List<Step>:
  match split:
    case True{}:
      [Remove{Certs.p("apiserver.crt")}, Remove{Certs.p("apiserver.key")}, CreateCert{Certs.apiserver(c, "server-ca")}]
    case False{}:
      []

# ensureKubeConfigsTrustServerCA: with split CAs, the kubeconfigs trust
# server-ca.
def Certs.trust_steps(split: Bool) -> +List<Step>:
  match split:
    case True{}:
      [ TrustCA{Certs.p("admin.conf"), Certs.p("server-ca.crt")},
        TrustCA{Certs.p("controller-manager.conf"), Certs.p("server-ca.crt")},
        TrustCA{Certs.p("scheduler.conf"), Certs.p("server-ca.crt")} ]
    case False{}:
      []

# kubeconfig.CreateJoinControlPlaneKubeConfigFiles (admin.conf for
# kubernetes-admin, controller-manager.conf, scheduler.conf), then
# super-admin.conf renamed to admin.conf.
def Certs.kubeconfig_steps(+c: Cfg) -> +List<Step>:
  [ CreateKubeconfig{Certs.kubeconfig(c, "admin.conf", "kubernetes-admin", ["kubeadm:cluster-admins"], False{})},
    CreateKubeconfig{Certs.kubeconfig(c, "controller-manager.conf", "system:kube-controller-manager", [], True{})},
    CreateKubeconfig{Certs.kubeconfig(c, "scheduler.conf", "system:kube-scheduler", [], True{})},
    CreateKubeconfig{Certs.kubeconfig(c, "super-admin.conf", "kubernetes-super-admin", ["system:masters"], False{})},
    Rename{Certs.p("super-admin.conf"), Certs.p("admin.conf")} ]

# generateCertificates: CreatePKIAssets (the certificates, then the
# service account keys), the kubeconfigs, splitCACert, then the split-CA
# fixes. The certificate and kubeconfig steps are built in parallel.
def Certs.generate_steps(+c: Cfg, +split: Bool) -> +List<Step>:
  certs kcs = Certs.create_certs(Certs.plan(c)) Certs.kubeconfig_steps(c)
  List.concat(&2, Step, [certs, [CreateSAKeys{}], kcs, Certs.split_ca_steps(), Certs.serving_steps(c, split), Certs.trust_steps(split)])

def Certs.backup_dir(+ts: String) -> String:
  Certs.data() ++ "/pki.bak/" ++ ts

# removeStandaloneEtcdCerts.
def Certs.etcd_removals() -> +List<Step>:
  [ Remove{Certs.p("etcd/peer.crt")}, Remove{Certs.p("etcd/peer.key")},
    Remove{Certs.p("etcd/server.crt")}, Remove{Certs.p("etcd/server.key")} ]

def Certs.ensure.if(expiring: Bool, +c: Cfg, split: Bool) -> +List<Step>:
  match expiring:
    case True{}:
      RemoveFiles{Certs.pki(), True{}} <> Certs.generate_steps(c, split)
    case False{}:
      []

# EnsureCerts in standalone mode: no ca.key, generate everything; else,
# when a leaf certificate needs renewal, remove the leaf files and
# generate what is missing.
def Certs.ensure_steps(ca_key: Bool, expiring: Bool, +c: Cfg, split: Bool) -> +List<Step>:
  match ca_key:
    case False{}:
      Certs.generate_steps(c, split)
    case True{}:
      Certs.ensure.if(expiring, c, split)

# Rotate (`certs rotate`; `certs rotate-ca` with with_ca) in standalone
# mode, at Unix time ts: back up, remove the leaf files (and the CA files
# with with_ca; never the service account keys), generate, remove the etcd
# server and peer certificates.
def Certs.rotation_steps(+c: Cfg, with_ca: Bool, +ts: String, split: Bool) -> +List<Step>:
  List.concat(&2, Step,
    [ [Backup{Certs.pki(), Certs.backup_dir(ts)}, RemoveFiles{Certs.pki(), Bool.not(with_ca)}],
      Certs.generate_steps(c, split),
      Certs.etcd_removals() ])

def Certs.watcher.if(expiring: Bool, +c: Cfg, +ts: String, split: Bool) -> +List<Step>:
  match expiring:
    case True{}:
      List.append(&2, Step, Certs.rotation_steps(c, False{}, ts, split),
        [ExitAfter{Certs.exit_delay_min_s(), Certs.exit_delay_max_s()}])
    case False{}:
      []

# One check of the cert watcher in standalone mode: nothing, or rotate the
# leaf certificates (backupPKI, rotateLeafCertsStandalone) and exit after
# a random delay (restartAfterRotation).
def Certs.watcher_steps(expiring: Bool, +c: Cfg, +ts: String, split: Bool) -> +List<Step>:
  Certs.watcher.if(expiring, c, ts, split)

# A modelled directory, for the copy steps.

def Certs.fs_has(fs: +List<PkiFile>, +p: String) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{PkiFile{q, d}, t}:
      Bool.or(String.eq(q, p), Certs.fs_has(t, p))

def Certs.fs_read.if(hit: Bool, d: String, rest: String) -> String:
  match hit:
    case True{}:
      d
    case False{}:
      rest

# The contents of p ("" when missing).
def Certs.fs_read(fs: +List<PkiFile>, +p: String) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{PkiFile{q, d}, t}:
      Certs.fs_read.if(String.eq(q, p), d, Certs.fs_read(t, p))

def Certs.copy.if(has: Bool, +fs: +List<PkiFile>, +dst: String, +data: String) -> +List<PkiFile>:
  match has:
    case True{}:
      fs
    case False{}:
      List.append(&2, PkiFile, fs, [PkiFile{dst, data}])

# copyFileIfNotExists (a file holds one PEM block, so the first block is
# the file).
def Certs.copy_if_missing(+fs: +List<PkiFile>, +src: String, +dst: String) -> +List<PkiFile>:
  Certs.copy.if(Certs.fs_has(fs, dst), fs, dst, Certs.fs_read(fs, src))

def Certs.run_step(s: Step, +fs: +List<PkiFile>) -> +List<PkiFile>:
  match s:
    case CopyCertIfMissing{src, dst}:
      Certs.copy_if_missing(fs, src, dst)
    case CopyIfMissing{src, dst}:
      Certs.copy_if_missing(fs, src, dst)
    case _:
      fs

# The copy steps run on a modelled directory; other steps do nothing.
def Certs.run(ss: +List<Step>, +fs: +List<PkiFile>) -> +List<PkiFile>:
  match ss:
    case Nil{}:
      fs
    case Con{s, t}:
      Certs.run(t, Certs.run_step(s, fs))

# Clustered mode (not used by vk8s): rolloutControlPlaneWithRetry patches
# the StatefulSet, else the Deployment; rolloutDeployedEtcdWithRetry
# patches <name>-etcd and ignores a missing one.
def Certs.rollout.deploy(deploy: Bool, +ns: String, +name: String, +at: String) -> Rollout:
  match deploy:
    case True{}:
      PatchDeployment{ns, name, Certs.rotation_annotation(), at}
    case False{}:
      RolloutError{"control-plane workload " ++ ns ++ "/" ++ name ++ " not found"}

def Certs.rollout_control_plane(sts: Bool, deploy: Bool, +ns: String, +name: String, +at: String) -> Rollout:
  match sts:
    case True{}:
      PatchStatefulSet{ns, name, Certs.rotation_annotation(), at}
    case False{}:
      Certs.rollout.deploy(deploy, ns, name, at)

def Certs.rollout_etcd(found: Bool, +ns: String, +name: String, +at: String) -> Rollout:
  match found:
    case True{}:
      PatchStatefulSet{ns, name ++ "-etcd", Certs.rotation_annotation(), at}
    case False{}:
      NoRollout{}
