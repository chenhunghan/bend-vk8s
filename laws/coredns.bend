import Base
import bend-kube-runtime@0.2.0.0/src/json.bend as J
import ../src/guest/coredns.bend as C

# Spec for src/guest/coredns.bend: the CoreDNS manifests vcluster deploys
# (pkg/coredns template.go, coredns.go; pkg/constants/coredns.go).
#
# The concrete laws transcribe every case of pkg/coredns/template_test.go
# (TestProcessManifests, TestProcessCorefile) and coredns_test.go
# (TestGetManifestVariablesImage), vcluster a8ab30e. Their inputs are the
# tests' config changes on config.NewDefaultConfig() (the part the
# templates read, C.Coredns.vcluster_defaults) or the tests' bare
# configs, and the tests' template variables; a variable a test leaves
# out is "". The expected texts are the tests' `want` strings, cut at
# their "---" lines into one fixture per document; vcluster's test
# compares them after strings.TrimSpace, and the output is trimmed. The
# pinned images and the label are pkg/constants/coredns.go.
#
# Each TestProcessManifests case is one law per document of its `want`
# (C.Coredns.doc.<kind> of the case's config is the fixture; the
# Deployment in two parts, cut at its containers) and one law for the
# case's branch. The general laws coredns.manifests_join,
# coredns.documents_<branch> and coredns.deployment_parts say that the
# manifests are the branch's documents joined by "---" lines. Together
# they state the whole `want`, and each law stays small enough for the
# BendTT kernel's fuel.
#
# That the manifest vk8s applies is scripts/guest/coredns.yaml (after
# rewrites that keep the YAML's meaning) is a test: tests/coredns.bend.

# Fixtures
# --------

# A bare config: controlPlane.coredns with the given fields only.
def coredns.fx.bare(fs: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"controlPlane", J.Json.obj([J.KV{"coredns", J.Json.obj(fs)}])}])

# A default config with one value changed.
def coredns.fx.with(path: List<&2, String>, v: J.Json) -> J.Json:
  C.Coredns.put(path, C.Coredns.vcluster_defaults(), v)

# The tests' variables {IMAGE: my-image, RUN_AS_USER: 1001, RUN_AS_GROUP: 1001}.
def coredns.fx.vars() -> C.Vars:
  C.Vars{"my-image", "1001", "1001", ""}

def coredns.fx.no_vars() -> C.Vars:
  C.Vars{"", "", "", ""}

def coredns.fx.num(+k: String, +n: String) -> J.KV:
  J.KV{k, J.JNum{n}}

# "should correctly set coreDNS security context": PodSecurityContext.
def coredns.fx.pod_security() -> J.Json:
  J.Json.obj([coredns.fx.num("runAsUser", "1042"), coredns.fx.num("runAsGroup", "2042"), coredns.fx.num("fsGroup", "3042")])

# ... and ContainerSecurityContext.
def coredns.fx.container_security() -> J.Json:
  J.Json.obj([coredns.fx.num("runAsUser", "1142"), coredns.fx.num("runAsGroup", "2242"),
    J.KV{"allowPrivilegeEscalation", J.JBool{False{}}},
    J.KV{"capabilities", J.Json.obj([J.KV{"drop", J.Json.arr([J.JStr{"ALL"}])},
      J.KV{"add", J.Json.arr([J.JStr{"NET_BIND_SERVICE"}])}])}])

# The ServiceAccount (every non-embedded `want`).
def coredns.fx.sa() -> String:
  "apiVersion: v1\n"
  ++ "kind: ServiceAccount\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system"

# The ClusterRole system:coredns.
def coredns.fx.cluster_role() -> String:
  "apiVersion: rbac.authorization.k8s.io/v1\n"
  ++ "kind: ClusterRole\n"
  ++ "metadata:\n"
  ++ "  labels:\n"
  ++ "    kubernetes.io/bootstrapping: rbac-defaults\n"
  ++ "  name: system:coredns\n"
  ++ "rules:\n"
  ++ "  - apiGroups:\n"
  ++ "      - \"\"\n"
  ++ "    resources:\n"
  ++ "      - endpoints\n"
  ++ "      - services\n"
  ++ "      - pods\n"
  ++ "      - namespaces\n"
  ++ "    verbs:\n"
  ++ "      - list\n"
  ++ "      - watch\n"
  ++ "  - apiGroups:\n"
  ++ "      - discovery.k8s.io\n"
  ++ "    resources:\n"
  ++ "      - endpointslices\n"
  ++ "    verbs:\n"
  ++ "      - list\n"
  ++ "      - watch"

# The ClusterRoleBinding system:coredns.
def coredns.fx.cluster_role_binding() -> String:
  "apiVersion: rbac.authorization.k8s.io/v1\n"
  ++ "kind: ClusterRoleBinding\n"
  ++ "metadata:\n"
  ++ "  annotations:\n"
  ++ "    rbac.authorization.kubernetes.io/autoupdate: \"true\"\n"
  ++ "  labels:\n"
  ++ "    kubernetes.io/bootstrapping: rbac-defaults\n"
  ++ "  name: system:coredns\n"
  ++ "roleRef:\n"
  ++ "  apiGroup: rbac.authorization.k8s.io\n"
  ++ "  kind: ClusterRole\n"
  ++ "  name: system:coredns\n"
  ++ "subjects:\n"
  ++ "  - kind: ServiceAccount\n"
  ++ "    name: coredns\n"
  ++ "    namespace: kube-system"

# The ConfigMap of "default" (Corefile for cluster.local).
def coredns.fx.configmap() -> String:
  "apiVersion: v1\n"
  ++ "kind: ConfigMap\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "data:\n"
  ++ "  Corefile: |-\n"
  ++ "    .:1053 {\n"
  ++ "        errors\n"
  ++ "        health\n"
  ++ "        ready\n"
  ++ "        rewrite name regex .*\\.nodes\\.vcluster\\.com kubernetes.default.svc.cluster.local\n"
  ++ "        kubernetes cluster.local in-addr.arpa ip6.arpa {\n"
  ++ "            pods insecure\n"
  ++ "            fallthrough in-addr.arpa ip6.arpa\n"
  ++ "        }\n"
  ++ "        hosts /etc/coredns/NodeHosts {\n"
  ++ "            ttl 60\n"
  ++ "            reload 15s\n"
  ++ "            fallthrough\n"
  ++ "        }\n"
  ++ "        prometheus :9153\n"
  ++ "        forward . /etc/resolv.conf\n"
  ++ "        cache 30\n"
  ++ "        loop\n"
  ++ "        reload\n"
  ++ "        loadbalance\n"
  ++ "    }\n"
  ++ "    \n"
  ++ "    import /etc/coredns/custom/*.server\n"
  ++ "  NodeHosts: \"\""

# The ConfigMap of "should correctly set custom coredns clusterdomain".
def coredns.fx.configmap_custom() -> String:
  "apiVersion: v1\n"
  ++ "kind: ConfigMap\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "data:\n"
  ++ "  Corefile: |-\n"
  ++ "    .:1053 {\n"
  ++ "        errors\n"
  ++ "        health\n"
  ++ "        ready\n"
  ++ "        rewrite name regex .*\\.nodes\\.vcluster\\.com kubernetes.default.svc.cluster.local\n"
  ++ "        kubernetes custom.local cluster.local in-addr.arpa ip6.arpa {\n"
  ++ "            pods insecure\n"
  ++ "            fallthrough in-addr.arpa ip6.arpa\n"
  ++ "        }\n"
  ++ "        hosts /etc/coredns/NodeHosts {\n"
  ++ "            ttl 60\n"
  ++ "            reload 15s\n"
  ++ "            fallthrough\n"
  ++ "        }\n"
  ++ "        prometheus :9153\n"
  ++ "        forward . /etc/resolv.conf\n"
  ++ "        cache 30\n"
  ++ "        loop\n"
  ++ "        reload\n"
  ++ "        loadbalance\n"
  ++ "    }\n"
  ++ "    \n"
  ++ "    import /etc/coredns/custom/*.server\n"
  ++ "  NodeHosts: \"\""

# The Deployment of "default", cut at its containers: the Deployment and
# its pod template ...
def coredns.fx.deployment_pod() -> String:
  "apiVersion: apps/v1\n"
  ++ "kind: Deployment\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "  labels:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"
  ++ "    kubernetes.io/name: \"CoreDNS\"\n"
  ++ "spec:\n"
  ++ "  replicas: 1\n"
  ++ "  strategy:\n"
  ++ "    type: RollingUpdate\n"
  ++ "    rollingUpdate:\n"
  ++ "      maxUnavailable: 1\n"
  ++ "  selector:\n"
  ++ "    matchLabels:\n"
  ++ "      k8s-app: vcluster-kube-dns\n"
  ++ "  template:\n"
  ++ "    metadata:\n"
  ++ "      labels:\n"
  ++ "        k8s-app: vcluster-kube-dns\n"
  ++ "    spec:\n"
  ++ "      priorityClassName: \"\"\n"
  ++ "      serviceAccountName: coredns\n"
  ++ "      nodeSelector:\n"
  ++ "        kubernetes.io/os: linux\n"
  ++ "      topologySpreadConstraints:\n"
  ++ "        - labelSelector:\n"
  ++ "            matchLabels:\n"
  ++ "              k8s-app: vcluster-kube-dns\n"
  ++ "          maxSkew: 1\n"
  ++ "          topologyKey: kubernetes.io/hostname\n"
  ++ "          whenUnsatisfiable: DoNotSchedule"

# ... its containers and volumes.
def coredns.fx.deployment_containers() -> String:
  "      containers:\n"
  ++ "        - name: coredns\n"
  ++ "          image: my-image\n"
  ++ "          imagePullPolicy: IfNotPresent\n"
  ++ "          resources:\n"
  ++ "            limits:\n"
  ++ "              cpu: 1000m\n"
  ++ "              memory: 170Mi\n"
  ++ "            requests:\n"
  ++ "              cpu: 20m\n"
  ++ "              memory: 64Mi\n"
  ++ "          args: [ \"-conf\", \"/etc/coredns/Corefile\" ]\n"
  ++ "          volumeMounts:\n"
  ++ "            - name: config-volume\n"
  ++ "              mountPath: /etc/coredns\n"
  ++ "              readOnly: true\n"
  ++ "            - name: custom-config-volume\n"
  ++ "              mountPath: /etc/coredns/custom\n"
  ++ "              readOnly: true\n"
  ++ "          securityContext:\n"
  ++ "            runAsNonRoot: true\n"
  ++ "            runAsUser: 1001\n"
  ++ "            runAsGroup: 1001\n"
  ++ "            allowPrivilegeEscalation: false\n"
  ++ "            capabilities:\n"
  ++ "              add:\n"
  ++ "                - NET_BIND_SERVICE\n"
  ++ "              drop:\n"
  ++ "                - ALL\n"
  ++ "            readOnlyRootFilesystem: true\n"
  ++ "          livenessProbe:\n"
  ++ "            httpGet:\n"
  ++ "              path: /health\n"
  ++ "              port: 8080\n"
  ++ "              scheme: HTTP\n"
  ++ "            initialDelaySeconds: 60\n"
  ++ "            periodSeconds: 10\n"
  ++ "            timeoutSeconds: 1\n"
  ++ "            successThreshold: 1\n"
  ++ "            failureThreshold: 3\n"
  ++ "          readinessProbe:\n"
  ++ "            httpGet:\n"
  ++ "              path: /ready\n"
  ++ "              port: 8181\n"
  ++ "              scheme: HTTP\n"
  ++ "            initialDelaySeconds: 0\n"
  ++ "            periodSeconds: 2\n"
  ++ "            timeoutSeconds: 1\n"
  ++ "            successThreshold: 1\n"
  ++ "            failureThreshold: 3\n"
  ++ "      dnsPolicy: Default\n"
  ++ "      volumes:\n"
  ++ "        - name: config-volume\n"
  ++ "          configMap:\n"
  ++ "            name: coredns\n"
  ++ "            items:\n"
  ++ "              - key: Corefile\n"
  ++ "                path: Corefile\n"
  ++ "              - key: NodeHosts\n"
  ++ "                path: NodeHosts\n"
  ++ "        - name: custom-config-volume\n"
  ++ "          configMap:\n"
  ++ "            name: coredns-custom\n"
  ++ "            optional: true"

# The Deployment of "should correctly set coreDNS security context", cut
# the same way: the Deployment and its pod template ...
def coredns.fx.deployment_security_pod() -> String:
  "apiVersion: apps/v1\n"
  ++ "kind: Deployment\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "  labels:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"
  ++ "    kubernetes.io/name: \"CoreDNS\"\n"
  ++ "spec:\n"
  ++ "  replicas: 1\n"
  ++ "  strategy:\n"
  ++ "    type: RollingUpdate\n"
  ++ "    rollingUpdate:\n"
  ++ "      maxUnavailable: 1\n"
  ++ "  selector:\n"
  ++ "    matchLabels:\n"
  ++ "      k8s-app: vcluster-kube-dns\n"
  ++ "  template:\n"
  ++ "    metadata:\n"
  ++ "      labels:\n"
  ++ "        k8s-app: vcluster-kube-dns\n"
  ++ "    spec:\n"
  ++ "      priorityClassName: \"\"\n"
  ++ "      serviceAccountName: coredns\n"
  ++ "      nodeSelector:\n"
  ++ "        kubernetes.io/os: linux\n"
  ++ "      topologySpreadConstraints:\n"
  ++ "        - labelSelector:\n"
  ++ "            matchLabels:\n"
  ++ "              k8s-app: vcluster-kube-dns\n"
  ++ "          maxSkew: 1\n"
  ++ "          topologyKey: kubernetes.io/hostname\n"
  ++ "          whenUnsatisfiable: DoNotSchedule\n"
  ++ "      securityContext:\n"
  ++ "        fsGroup: 3042\n"
  ++ "        runAsGroup: 2042\n"
  ++ "        runAsUser: 1042"

# ... its containers and volumes.
def coredns.fx.deployment_security_containers() -> String:
  "      containers:\n"
  ++ "        - name: coredns\n"
  ++ "          image: my-image\n"
  ++ "          imagePullPolicy: IfNotPresent\n"
  ++ "          resources:\n"
  ++ "            limits:\n"
  ++ "              cpu: 1000m\n"
  ++ "              memory: 170Mi\n"
  ++ "            requests:\n"
  ++ "              cpu: 20m\n"
  ++ "              memory: 64Mi\n"
  ++ "          args: [ \"-conf\", \"/etc/coredns/Corefile\" ]\n"
  ++ "          volumeMounts:\n"
  ++ "            - name: config-volume\n"
  ++ "              mountPath: /etc/coredns\n"
  ++ "              readOnly: true\n"
  ++ "            - name: custom-config-volume\n"
  ++ "              mountPath: /etc/coredns/custom\n"
  ++ "              readOnly: true\n"
  ++ "          securityContext:\n"
  ++ "            allowPrivilegeEscalation: false\n"
  ++ "            capabilities:\n"
  ++ "              add:\n"
  ++ "              - NET_BIND_SERVICE\n"
  ++ "              drop:\n"
  ++ "              - ALL\n"
  ++ "            runAsGroup: 2242\n"
  ++ "            runAsUser: 1142\n"
  ++ "          livenessProbe:\n"
  ++ "            httpGet:\n"
  ++ "              path: /health\n"
  ++ "              port: 8080\n"
  ++ "              scheme: HTTP\n"
  ++ "            initialDelaySeconds: 60\n"
  ++ "            periodSeconds: 10\n"
  ++ "            timeoutSeconds: 1\n"
  ++ "            successThreshold: 1\n"
  ++ "            failureThreshold: 3\n"
  ++ "          readinessProbe:\n"
  ++ "            httpGet:\n"
  ++ "              path: /ready\n"
  ++ "              port: 8181\n"
  ++ "              scheme: HTTP\n"
  ++ "            initialDelaySeconds: 0\n"
  ++ "            periodSeconds: 2\n"
  ++ "            timeoutSeconds: 1\n"
  ++ "            successThreshold: 1\n"
  ++ "            failureThreshold: 3\n"
  ++ "      dnsPolicy: Default\n"
  ++ "      volumes:\n"
  ++ "        - name: config-volume\n"
  ++ "          configMap:\n"
  ++ "            name: coredns\n"
  ++ "            items:\n"
  ++ "              - key: Corefile\n"
  ++ "                path: Corefile\n"
  ++ "              - key: NodeHosts\n"
  ++ "                path: NodeHosts\n"
  ++ "        - name: custom-config-volume\n"
  ++ "          configMap:\n"
  ++ "            name: coredns-custom\n"
  ++ "            optional: true"

# The Service of "default".
def coredns.fx.service() -> String:
  "apiVersion: v1\n"
  ++ "kind: Service\n"
  ++ "metadata:\n"
  ++ "  name: kube-dns\n"
  ++ "  namespace: kube-system\n"
  ++ "  annotations:\n"
  ++ "    prometheus.io/port: \"9153\"\n"
  ++ "    prometheus.io/scrape: \"true\"\n"
  ++ "  labels:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"
  ++ "    kubernetes.io/cluster-service: \"true\"\n"
  ++ "    kubernetes.io/name: \"CoreDNS\"\n"
  ++ "spec:\n"
  ++ "  type: ClusterIP\n"
  ++ "  selector:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"
  ++ "  ports:\n"
  ++ "    - name: dns\n"
  ++ "      port: 53\n"
  ++ "      targetPort: 1053\n"
  ++ "      protocol: UDP\n"
  ++ "    - name: dns-tcp\n"
  ++ "      port: 53\n"
  ++ "      targetPort: 1053\n"
  ++ "      protocol: TCP\n"
  ++ "    - name: metrics\n"
  ++ "      port: 9153\n"
  ++ "      protocol: TCP"

# The ConfigMap of TestProcessManifests "embedded".
def coredns.fx.embedded_configmap() -> String:
  "apiVersion: v1\n"
  ++ "kind: ConfigMap\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "data:\n"
  ++ "  NodeHosts: \"\""

# The Service of TestProcessManifests "embedded".
def coredns.fx.embedded_service() -> String:
  "apiVersion: v1\n"
  ++ "kind: Service\n"
  ++ "metadata:\n"
  ++ "  name: kube-dns\n"
  ++ "  namespace: kube-system\n"
  ++ "  annotations:\n"
  ++ "    prometheus.io/port: \"9153\"\n"
  ++ "    prometheus.io/scrape: \"true\"\n"
  ++ "  labels:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"
  ++ "    kubernetes.io/cluster-service: \"true\"\n"
  ++ "    kubernetes.io/name: \"CoreDNS\"\n"
  ++ "spec:\n"
  ++ "  type: ClusterIP\n"
  ++ "  ports:\n"
  ++ "    - name: dns\n"
  ++ "      port: 53\n"
  ++ "      targetPort: 1053\n"
  ++ "      protocol: UDP\n"
  ++ "    - name: dns-tcp\n"
  ++ "      port: 53\n"
  ++ "      targetPort: 1053\n"
  ++ "      protocol: TCP\n"
  ++ "    - name: metrics\n"
  ++ "      port: 9153\n"
  ++ "      protocol: TCP"

# TestProcessCorefile "embedded".
def coredns.fx.corefile_embedded() -> String:
  ".:1053 {\n"
  ++ "    errors\n"
  ++ "    health\n"
  ++ "    ready\n"
  ++ "    kubernetes cluster.local in-addr.arpa ip6.arpa {\n"
  ++ "        kubeconfig /data/vcluster/admin.conf\n"
  ++ "        pods insecure\n"
  ++ "        fallthrough in-addr.arpa ip6.arpa\n"
  ++ "    }\n"
  ++ "    hosts /etc/coredns/NodeHosts {\n"
  ++ "        ttl 60\n"
  ++ "        reload 15s\n"
  ++ "        fallthrough\n"
  ++ "    }\n"
  ++ "    prometheus :9153\n"
  ++ "    forward . /etc/resolv.conf\n"
  ++ "    cache 30\n"
  ++ "    loop\n"
  ++ "    loadbalance\n"
  ++ "}\n"
  ++ "\n"
  ++ "import /etc/coredns/custom/*.server"

# TestProcessManifests (pkg/coredns/template_test.go)
# --------------------------------------------------

# "default"
def coredns.fx.default.v() -> J.Json:
  C.Coredns.vcluster_defaults()

def coredns.fx.default.vs() -> C.Vars:
  coredns.fx.vars()

law coredns.manifests_default.branch:
  {C.Coredns.branch(coredns.fx.default.v()) == C.Full{} : C.Branch}

law coredns.manifests_default.service_account:
  {C.Coredns.doc.service_account(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.sa() : String}

law coredns.manifests_default.cluster_role:
  {C.Coredns.doc.cluster_role(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.cluster_role() : String}

law coredns.manifests_default.cluster_role_binding:
  {C.Coredns.doc.cluster_role_binding(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.cluster_role_binding() : String}

law coredns.manifests_default.configmap:
  {C.Coredns.doc.configmap(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.configmap() : String}

law coredns.manifests_default.deployment_pod:
  {C.Coredns.doc.deployment.pod(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.deployment_pod() : String}

law coredns.manifests_default.deployment_containers:
  {C.Coredns.doc.deployment.containers(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.deployment_containers() : String}

law coredns.manifests_default.service:
  {C.Coredns.doc.service(coredns.fx.default.v(), coredns.fx.default.vs())
    == coredns.fx.service() : String}

# "overwrite"
def coredns.fx.overwrite.v() -> J.Json:
  coredns.fx.bare([J.KV{"enabled", J.JBool{True{}}}, J.KV{"overwriteManifests", J.JStr{"abc"}}])

law coredns.manifests_overwrite.branch:
  {C.Coredns.branch(coredns.fx.overwrite.v()) == C.Overwrite{} : C.Branch}

law coredns.manifests_overwrite.overwrite:
  {C.Coredns.doc.overwrite(coredns.fx.overwrite.v(), coredns.fx.no_vars()) == "abc" : String}

# "embedded"
def coredns.fx.embedded.v() -> J.Json:
  coredns.fx.with(["controlPlane", "coredns", "embedded"], J.JBool{True{}})

law coredns.manifests_embedded.branch:
  {C.Coredns.branch(coredns.fx.embedded.v()) == C.Embedded{} : C.Branch}

law coredns.manifests_embedded.configmap:
  {C.Coredns.doc.embedded_configmap(coredns.fx.embedded.v(), coredns.fx.no_vars())
    == coredns.fx.embedded_configmap() : String}

law coredns.manifests_embedded.service:
  {C.Coredns.doc.embedded_service(coredns.fx.embedded.v(), coredns.fx.no_vars())
    == coredns.fx.embedded_service() : String}

# "should correctly set default coredns clusterdomain"
# (its `want` is the text of "default")
def coredns.fx.default_domain.v() -> J.Json:
  coredns.fx.with(["networking", "advanced", "clusterDomain"], J.JStr{"cluster.local"})

def coredns.fx.default_domain.vs() -> C.Vars:
  coredns.fx.vars()

law coredns.manifests_default_cluster_domain.branch:
  {C.Coredns.branch(coredns.fx.default_domain.v()) == C.Full{} : C.Branch}

law coredns.manifests_default_cluster_domain.service_account:
  {C.Coredns.doc.service_account(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.sa() : String}

law coredns.manifests_default_cluster_domain.cluster_role:
  {C.Coredns.doc.cluster_role(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.cluster_role() : String}

law coredns.manifests_default_cluster_domain.cluster_role_binding:
  {C.Coredns.doc.cluster_role_binding(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.cluster_role_binding() : String}

law coredns.manifests_default_cluster_domain.configmap:
  {C.Coredns.doc.configmap(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.configmap() : String}

law coredns.manifests_default_cluster_domain.deployment_pod:
  {C.Coredns.doc.deployment.pod(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.deployment_pod() : String}

law coredns.manifests_default_cluster_domain.deployment_containers:
  {C.Coredns.doc.deployment.containers(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.deployment_containers() : String}

law coredns.manifests_default_cluster_domain.service:
  {C.Coredns.doc.service(coredns.fx.default_domain.v(), coredns.fx.default_domain.vs())
    == coredns.fx.service() : String}

# "should correctly set custom coredns clusterdomain"
def coredns.fx.custom_domain.v() -> J.Json:
  coredns.fx.with(["networking", "advanced", "clusterDomain"], J.JStr{"custom.local"})

def coredns.fx.custom_domain.vs() -> C.Vars:
  coredns.fx.vars()

law coredns.manifests_custom_cluster_domain.branch:
  {C.Coredns.branch(coredns.fx.custom_domain.v()) == C.Full{} : C.Branch}

law coredns.manifests_custom_cluster_domain.service_account:
  {C.Coredns.doc.service_account(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.sa() : String}

law coredns.manifests_custom_cluster_domain.cluster_role:
  {C.Coredns.doc.cluster_role(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.cluster_role() : String}

law coredns.manifests_custom_cluster_domain.cluster_role_binding:
  {C.Coredns.doc.cluster_role_binding(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.cluster_role_binding() : String}

law coredns.manifests_custom_cluster_domain.configmap:
  {C.Coredns.doc.configmap(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.configmap_custom() : String}

law coredns.manifests_custom_cluster_domain.deployment_pod:
  {C.Coredns.doc.deployment.pod(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.deployment_pod() : String}

law coredns.manifests_custom_cluster_domain.deployment_containers:
  {C.Coredns.doc.deployment.containers(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.deployment_containers() : String}

law coredns.manifests_custom_cluster_domain.service:
  {C.Coredns.doc.service(coredns.fx.custom_domain.v(), coredns.fx.custom_domain.vs())
    == coredns.fx.service() : String}

# "should correctly set coreDNS security context"
# (variables: IMAGE only)
def coredns.fx.security.v() -> J.Json:
  C.Coredns.put(["controlPlane", "coredns", "security", "containerSecurityContext"],
    coredns.fx.with(["controlPlane", "coredns", "security", "podSecurityContext"], coredns.fx.pod_security()),
    coredns.fx.container_security())

def coredns.fx.security.vs() -> C.Vars:
  C.Vars{"my-image", "", "", ""}

law coredns.manifests_security_context.branch:
  {C.Coredns.branch(coredns.fx.security.v()) == C.Full{} : C.Branch}

law coredns.manifests_security_context.service_account:
  {C.Coredns.doc.service_account(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.sa() : String}

law coredns.manifests_security_context.cluster_role:
  {C.Coredns.doc.cluster_role(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.cluster_role() : String}

law coredns.manifests_security_context.cluster_role_binding:
  {C.Coredns.doc.cluster_role_binding(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.cluster_role_binding() : String}

law coredns.manifests_security_context.configmap:
  {C.Coredns.doc.configmap(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.configmap() : String}

law coredns.manifests_security_context.deployment_pod:
  {C.Coredns.doc.deployment.pod(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.deployment_security_pod() : String}

law coredns.manifests_security_context.deployment_containers:
  {C.Coredns.doc.deployment.containers(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.deployment_security_containers() : String}

law coredns.manifests_security_context.service:
  {C.Coredns.doc.service(coredns.fx.security.v(), coredns.fx.security.vs())
    == coredns.fx.service() : String}

# The stream (template.go processManifests): the branch picks the
# documents, and the manifests are the documents joined by "---" lines.
# With these, the laws above give each case's whole `want`: its branch,
# then its documents in order.

law coredns.manifests_join:
  for +v: J.Json
  for +vs: C.Vars
  {C.Coredns.manifests(v, vs) == C.Coredns.join(C.Coredns.documents.of(C.Coredns.branch(v), v, vs)) : String}

law coredns.documents_full:
  for +v: J.Json
  for +vs: C.Vars
  {C.Coredns.documents.of(C.Full{}, v, vs)
    == [C.Coredns.doc.service_account(v, vs), C.Coredns.doc.cluster_role(v, vs),
        C.Coredns.doc.cluster_role_binding(v, vs), C.Coredns.doc.configmap(v, vs), C.Coredns.doc.deployment(v, vs),
        C.Coredns.doc.service(v, vs)] : List<&2, String>}

# The Deployment is its two parts, joined at the containers.
law coredns.deployment_parts:
  for +v: J.Json
  for +vs: C.Vars
  {C.Coredns.doc.deployment(v, vs)
    == C.Coredns.doc.deployment.pod(v, vs) ++ "\n" ++ C.Coredns.doc.deployment.containers(v, vs) : String}

law coredns.documents_embedded:
  for +v: J.Json
  for +vs: C.Vars
  {C.Coredns.documents.of(C.Embedded{}, v, vs)
    == [C.Coredns.doc.embedded_configmap(v, vs), C.Coredns.doc.embedded_service(v, vs)] : List<&2, String>}

law coredns.documents_overwrite:
  for +v: J.Json
  for +vs: C.Vars
  {C.Coredns.documents.of(C.Overwrite{}, v, vs) == [C.Coredns.doc.overwrite(v, vs)] : List<&2, String>}

# TestProcessCorefile (pkg/coredns/template_test.go)
# -------------------------------------------------

# "embedded"
law coredns.corefile_embedded:
  {C.Coredns.corefile(coredns.fx.bare([J.KV{"enabled", J.JBool{True{}}}, J.KV{"embedded", J.JBool{True{}}}]),
    coredns.fx.no_vars()) == coredns.fx.corefile_embedded() : String}

# "overwrite"
law coredns.corefile_overwrite:
  {C.Coredns.corefile(coredns.fx.bare([J.KV{"enabled", J.JBool{True{}}}, J.KV{"embedded", J.JBool{True{}}},
    J.KV{"overwriteConfig", J.JStr{"abc"}}]), coredns.fx.no_vars()) == "abc" : String}

# TestGetManifestVariablesImage (pkg/coredns/coredns_test.go)
# ----------------------------------------------------------

# "known version is fully qualified with docker.io"
law coredns.image_known_version:
  {C.Coredns.image("1", "34", "") == "docker.io/coredns/coredns:1.12.1" : String}

# "unknown version falls back to fully qualified default image"
law coredns.image_unknown_version:
  {C.Coredns.image("1", "99", "") == "docker.io/" ++ "coredns/coredns:1.14.2" : String}

# "custom registry takes precedence over docker.io"
law coredns.image_custom_registry:
  {C.Coredns.image("1", "34", "my.registry:5000") == "my.registry:5000/coredns/coredns:1.12.1" : String}

# "custom registry trailing slash is trimmed"
law coredns.image_registry_trailing_slash:
  {C.Coredns.image("1", "34", "my.registry:5000/") == "my.registry:5000/coredns/coredns:1.12.1" : String}

# pkg/constants/coredns.go and coredns.go DefaultImage
# ----------------------------------------------------

law coredns.pinned_1_36:
  {C.Coredns.pinned("1.36") == Some{"coredns/coredns:1.14.2"} : Maybe<&2, String>}

law coredns.pinned_1_35:
  {C.Coredns.pinned("1.35") == Some{"coredns/coredns:1.14.1"} : Maybe<&2, String>}

law coredns.pinned_1_34:
  {C.Coredns.pinned("1.34") == Some{"coredns/coredns:1.12.1"} : Maybe<&2, String>}

law coredns.pinned_1_33:
  {C.Coredns.pinned("1.33") == Some{"coredns/coredns:1.12.0"} : Maybe<&2, String>}

law coredns.pinned_1_32:
  {C.Coredns.pinned("1.32") == Some{"coredns/coredns:1.11.3"} : Maybe<&2, String>}

law coredns.pinned_1_31:
  {C.Coredns.pinned("1.31") == Some{"coredns/coredns:1.11.3"} : Maybe<&2, String>}

law coredns.pinned_1_30:
  {C.Coredns.pinned("1.30") == Some{"coredns/coredns:1.11.3"} : Maybe<&2, String>}

law coredns.pinned_none:
  {C.Coredns.pinned("1.29") == None{} : Maybe<&2, String>}

law coredns.default_image:
  {C.Coredns.default_image() == "coredns/coredns:1.14.2" : String}

law coredns.label:
  {C.Coredns.label_key() ++ ": " ++ C.Coredns.label_value() == "k8s-app: vcluster-kube-dns" : String}

# vk8s
# ----

law coredns.default_manifest_renders:
  {C.Coredns.default_manifest()
    == C.Coredns.manifests(C.Coredns.values(C.Coredns.default_cfg()), C.Coredns.vars(C.Coredns.default_cfg())) : String}

# General laws: each field of the vk8s config reaches the place in
# vcluster's config or variables that the templates read.

law coredns.render_is_manifests:
  for +cfg: C.Cfg
  {C.Coredns.render(cfg) == C.Coredns.manifests(C.Coredns.values(cfg), C.Coredns.vars(cfg)) : String}

law coredns.values_cluster_domain:
  for +d: String
  for +ip: String
  for +img: String
  for +r: U32
  for +u: U32
  for +g: U32
  {J.Json.at(C.Coredns.values(C.Cfg{d, ip, img, r, u, g}), ["networking", "advanced", "clusterDomain"]) == J.JStr{d} : J.Json}

law coredns.values_service_ip:
  for +d: String
  for +ip: String
  for +img: String
  for +r: U32
  for +u: U32
  for +g: U32
  {J.Json.at(C.Coredns.values(C.Cfg{d, ip, img, r, u, g}), ["controlPlane", "coredns", "service", "spec", "clusterIP"])
    == J.JStr{ip} : J.Json}

law coredns.values_replicas:
  for +d: String
  for +ip: String
  for +img: String
  for +r: U32
  for +u: U32
  for +g: U32
  {J.Json.at(C.Coredns.values(C.Cfg{d, ip, img, r, u, g}), ["controlPlane", "coredns", "deployment", "replicas"])
    == J.JNum{U32.show(r)} : J.Json}

# No kubelet proxy by hostname in vk8s: the Corefile has no rewrite rule.
law coredns.values_no_rewrite:
  for +d: String
  for +ip: String
  for +img: String
  for +r: U32
  for +u: U32
  for +g: U32
  {J.Json.at(C.Coredns.values(C.Cfg{d, ip, img, r, u, g}), ["networking", "advanced", "proxyKubelets", "byHostname"])
    == J.JBool{False{}} : J.Json}

law coredns.vars_of_cfg:
  for +d: String
  for +ip: String
  for +img: String
  for +r: U32
  for +u: U32
  for +g: U32
  {C.Coredns.vars(C.Cfg{d, ip, img, r, u, g}) == C.Vars{img, U32.show(u), U32.show(g), "/etc/resolv.conf"} : C.Vars}
