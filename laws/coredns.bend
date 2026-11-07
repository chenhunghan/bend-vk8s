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
# coredns.default_matches_static_file states that the manifest vk8s
# applies is scripts/guest/coredns.yaml (its bytes in coredns.fx.file),
# after the rewrites listed there: each turns a flow-style or reordered
# part of that hand-compacted file back into the text vcluster's template
# writes, or drops what the template cannot write (the comments). Every
# rewrite keeps the YAML's meaning, but for priorityClassName: "", which
# the API reads as unset.

# Fixtures
# --------

def coredns.fx.doc(+a: String, +b: String) -> String:
  a ++ "\n---\n" ++ b

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

# The Deployment of "default".
def coredns.fx.deployment() -> String:
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
  ++ "      containers:\n"
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

# The Deployment of "should correctly set coreDNS security context".
def coredns.fx.deployment_security() -> String:
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
  ++ "        runAsUser: 1042\n"
  ++ "      containers:\n"
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

# TestProcessManifests "default" (and "should correctly set default coredns
# clusterdomain", whose `want` is the same text).
def coredns.fx.manifests(cm: String, dep: String) -> String:
  coredns.fx.doc(coredns.fx.sa(), coredns.fx.doc(coredns.fx.cluster_role(), coredns.fx.doc(coredns.fx.cluster_role_binding(),
    coredns.fx.doc(cm, coredns.fx.doc(dep, coredns.fx.service())))))

# scripts/guest/coredns.yaml, byte for byte.
def coredns.fx.file() -> String:
  "# vcluster pkg/coredns/template.go, rendered with the default values\n"
  ++ "# (controlPlane.coredns, image coredns/coredns:1.14.2 for Kubernetes 1.36,\n"
  ++ "# RUN_AS_USER/GROUP 1001), and the kube-dns Service at 10.96.0.10 (kubelet's\n"
  ++ "# clusterDNS). To be generated by Bend with laws (TODO: src/guest/coredns.bend).\n"
  ++ "apiVersion: v1\n"
  ++ "kind: ServiceAccount\n"
  ++ "metadata:\n"
  ++ "  name: coredns\n"
  ++ "  namespace: kube-system\n"
  ++ "---\n"
  ++ "apiVersion: rbac.authorization.k8s.io/v1\n"
  ++ "kind: ClusterRole\n"
  ++ "metadata:\n"
  ++ "  labels:\n"
  ++ "    kubernetes.io/bootstrapping: rbac-defaults\n"
  ++ "  name: system:coredns\n"
  ++ "rules:\n"
  ++ "  - apiGroups: [\"\"]\n"
  ++ "    resources: [endpoints, services, pods, namespaces]\n"
  ++ "    verbs: [list, watch]\n"
  ++ "  - apiGroups: [discovery.k8s.io]\n"
  ++ "    resources: [endpointslices]\n"
  ++ "    verbs: [list, watch]\n"
  ++ "---\n"
  ++ "apiVersion: rbac.authorization.k8s.io/v1\n"
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
  ++ "    namespace: kube-system\n"
  ++ "---\n"
  ++ "apiVersion: v1\n"
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
  ++ "\n"
  ++ "    import /etc/coredns/custom/*.server\n"
  ++ "  NodeHosts: \"\"\n"
  ++ "---\n"
  ++ "apiVersion: apps/v1\n"
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
  ++ "      serviceAccountName: coredns\n"
  ++ "      nodeSelector:\n"
  ++ "        kubernetes.io/os: linux\n"
  ++ "      securityContext:\n"
  ++ "        seccompProfile:\n"
  ++ "          type: RuntimeDefault\n"
  ++ "      containers:\n"
  ++ "        - name: coredns\n"
  ++ "          image: coredns/coredns:1.14.2\n"
  ++ "          imagePullPolicy: IfNotPresent\n"
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
  ++ "              add: [NET_BIND_SERVICE]\n"
  ++ "              drop: [ALL]\n"
  ++ "            readOnlyRootFilesystem: true\n"
  ++ "          livenessProbe:\n"
  ++ "            httpGet: {path: /health, port: 8080, scheme: HTTP}\n"
  ++ "            initialDelaySeconds: 60\n"
  ++ "            periodSeconds: 10\n"
  ++ "            timeoutSeconds: 1\n"
  ++ "            successThreshold: 1\n"
  ++ "            failureThreshold: 3\n"
  ++ "          readinessProbe:\n"
  ++ "            httpGet: {path: /ready, port: 8181, scheme: HTTP}\n"
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
  ++ "            optional: true\n"
  ++ "---\n"
  ++ "apiVersion: v1\n"
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
  ++ "  clusterIP: 10.96.0.10\n"
  ++ "  ports:\n"
  ++ "    - {name: dns, port: 53, targetPort: 1053, protocol: UDP}\n"
  ++ "    - {name: dns-tcp, port: 53, targetPort: 1053, protocol: TCP}\n"
  ++ "    - {name: metrics, port: 9153, protocol: TCP}\n"
  ++ "  selector:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"

# The leading comment lines: YAML comments, not in vcluster's output.
def coredns.fx.header.from() -> String:
  "# vcluster pkg/coredns/template.go, rendered with the default values\n"
  ++ "# (controlPlane.coredns, image coredns/coredns:1.14.2 for Kubernetes 1.36,\n"
  ++ "# RUN_AS_USER/GROUP 1001), and the kube-dns Service at 10.96.0.10 (kubelet's\n"
  ++ "# clusterDNS). To be generated by Bend with laws (TODO: src/guest/coredns.bend).\n"

def coredns.fx.header.to() -> String:
  ""

# The ClusterRole rules in flow style; the template writes block lists.
def coredns.fx.rules.from() -> String:
  "  - apiGroups: [\"\"]\n"
  ++ "    resources: [endpoints, services, pods, namespaces]\n"
  ++ "    verbs: [list, watch]\n"
  ++ "  - apiGroups: [discovery.k8s.io]\n"
  ++ "    resources: [endpointslices]\n"
  ++ "    verbs: [list, watch]\n"

def coredns.fx.rules.to() -> String:
  "  - apiGroups:\n"
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
  ++ "      - watch\n"

# The Corefile's blank line: the template's `indent 4` pads it to four
# spaces (a |- block keeps it an empty line either way).
def coredns.fx.blank.from() -> String:
  "    }\n"
  ++ "\n"
  ++ "    import /etc/coredns/custom/*.server\n"

def coredns.fx.blank.to() -> String:
  "    }\n"
  ++ "    \n"
  ++ "    import /etc/coredns/custom/*.server\n"

# priorityClassName: the template always writes it, "" when unset, which
# the API reads as unset.
def coredns.fx.priority.from() -> String:
  "    spec:\n"
  ++ "      serviceAccountName: coredns\n"

def coredns.fx.priority.to() -> String:
  "    spec:\n"
  ++ "      priorityClassName: \"\"\n"
  ++ "      serviceAccountName: coredns\n"

# The capabilities in flow style; the template writes block lists.
def coredns.fx.caps.from() -> String:
  "              add: [NET_BIND_SERVICE]\n"
  ++ "              drop: [ALL]\n"

def coredns.fx.caps.to() -> String:
  "              add:\n"
  ++ "                - NET_BIND_SERVICE\n"
  ++ "              drop:\n"
  ++ "                - ALL\n"

# The liveness probe in flow style; the template writes a block map.
def coredns.fx.liveness.from() -> String:
  "            httpGet: {path: /health, port: 8080, scheme: HTTP}\n"

def coredns.fx.liveness.to() -> String:
  "            httpGet:\n"
  ++ "              path: /health\n"
  ++ "              port: 8080\n"
  ++ "              scheme: HTTP\n"

# The readiness probe in flow style; the template writes a block map.
def coredns.fx.readiness.from() -> String:
  "            httpGet: {path: /ready, port: 8181, scheme: HTTP}\n"

def coredns.fx.readiness.to() -> String:
  "            httpGet:\n"
  ++ "              path: /ready\n"
  ++ "              port: 8181\n"
  ++ "              scheme: HTTP\n"

# The Service ports in flow style before the selector; the template
# writes the selector, then the ports as block maps.
def coredns.fx.ports.from() -> String:
  "  ports:\n"
  ++ "    - {name: dns, port: 53, targetPort: 1053, protocol: UDP}\n"
  ++ "    - {name: dns-tcp, port: 53, targetPort: 1053, protocol: TCP}\n"
  ++ "    - {name: metrics, port: 9153, protocol: TCP}\n"
  ++ "  selector:\n"
  ++ "    k8s-app: vcluster-kube-dns\n"

def coredns.fx.ports.to() -> String:
  "  selector:\n"
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
  ++ "      protocol: TCP\n"

# The rewrites in order, then vcluster's strings.TrimSpace (the file
# ends with a newline).
def coredns.fx.normalize(s: String) -> String:
  s1 = C.Coredns.replace(s, coredns.fx.header.from(), coredns.fx.header.to())
  s2 = C.Coredns.replace(s1, coredns.fx.rules.from(), coredns.fx.rules.to())
  s3 = C.Coredns.replace(s2, coredns.fx.blank.from(), coredns.fx.blank.to())
  s4 = C.Coredns.replace(s3, coredns.fx.priority.from(), coredns.fx.priority.to())
  s5 = C.Coredns.replace(s4, coredns.fx.caps.from(), coredns.fx.caps.to())
  s6 = C.Coredns.replace(s5, coredns.fx.liveness.from(), coredns.fx.liveness.to())
  s7 = C.Coredns.replace(s6, coredns.fx.readiness.from(), coredns.fx.readiness.to())
  s8 = C.Coredns.replace(s7, coredns.fx.ports.from(), coredns.fx.ports.to())
  String.trim(s8)

# TestProcessManifests (pkg/coredns/template_test.go)
# --------------------------------------------------

# "default"
law coredns.manifests_default:
  {C.Coredns.manifests(C.Coredns.vcluster_defaults(), coredns.fx.vars())
    == coredns.fx.manifests(coredns.fx.configmap(), coredns.fx.deployment()) : String}

# "overwrite"
law coredns.manifests_overwrite:
  {C.Coredns.manifests(coredns.fx.bare([J.KV{"enabled", J.JBool{True{}}}, J.KV{"overwriteManifests", J.JStr{"abc"}}]),
    coredns.fx.no_vars()) == "abc" : String}

# "embedded"
law coredns.manifests_embedded:
  {C.Coredns.manifests(coredns.fx.with(["controlPlane", "coredns", "embedded"], J.JBool{True{}}), coredns.fx.no_vars())
    == coredns.fx.doc(coredns.fx.embedded_configmap(), coredns.fx.embedded_service()) : String}

# "should correctly set default coredns clusterdomain"
law coredns.manifests_default_cluster_domain:
  {C.Coredns.manifests(coredns.fx.with(["networking", "advanced", "clusterDomain"], J.JStr{"cluster.local"}),
    coredns.fx.vars()) == coredns.fx.manifests(coredns.fx.configmap(), coredns.fx.deployment()) : String}

# "should correctly set custom coredns clusterdomain"
law coredns.manifests_custom_cluster_domain:
  {C.Coredns.manifests(coredns.fx.with(["networking", "advanced", "clusterDomain"], J.JStr{"custom.local"}),
    coredns.fx.vars()) == coredns.fx.manifests(coredns.fx.configmap_custom(), coredns.fx.deployment()) : String}

# "should correctly set coreDNS security context" (variables: IMAGE only)
law coredns.manifests_security_context:
  {C.Coredns.manifests(C.Coredns.put(["controlPlane", "coredns", "security", "containerSecurityContext"],
    coredns.fx.with(["controlPlane", "coredns", "security", "podSecurityContext"], coredns.fx.pod_security()),
    coredns.fx.container_security()), C.Vars{"my-image", "", "", ""})
    == coredns.fx.manifests(coredns.fx.configmap(), coredns.fx.deployment_security()) : String}

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

# The manifest vk8s applies is scripts/guest/coredns.yaml, after the
# rewrites in coredns.fx.normalize.
law coredns.default_matches_static_file:
  {coredns.fx.normalize(coredns.fx.file()) == C.Coredns.default_manifest() : String}

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
