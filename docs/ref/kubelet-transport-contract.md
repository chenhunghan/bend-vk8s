# Fake kubelet: transport prerequisite

The fake-kubelet implementation is not complete. This note records a
transport interface gap found before implementation. It does not change
the architecture or mark the task complete.

## Source versions

- bend-vk8s main: `3a2bab1a386893ccda000586cfc38f364c1d1578`.
- vcluster: `a8ab30eab6f27b183a80783f4e5854c1a2eb6ef5`.
- bend-kube v0.3.0: `43d4a9740c085757fa5978b8707ff808b7df3d0b`,
  published package name `bend-kube-runtime@0.3.0.0`.

The findings below come from source inspection. No Go tests, Bend tests,
builds, proofs, or integration tests ran in the implementer sandbox.
The factory rules reserve these checks for CI.

## The two TLS interfaces do not share connections

The requested upstream connection uses
[`N.Tls.open`](https://github.com/chenhunghan/bend-kube/blob/43d4a9740c085757fa5978b8707ff808b7df3d0b/src/net.bend#L164).
It returns a `Socket`. The associated OpenSSL object lives in the
client's private
[`tls_conn`](https://github.com/chenhunghan/bend-kube/blob/43d4a9740c085757fa5978b8707ff808b7df3d0b/src/effs/tls.c#L74)
table. The public interface has send, receive and close effects, but no
connection-transfer or splice effect.

The downstream server uses `host/tls_server.bend`. Its OpenSSL objects
live in a different table, `tsv_conn`, in `host/effs/tls_server.c:89`.
`TlsSrv.splice` selects TLS only when a descriptor occurs in that table
(`host/effs/tls_server.c:906`). Otherwise it uses raw `recv` and `send`.
It also closes both connections through `tsv_end`, which only clears the
server table.

Thus, passing an `N.Tls.open` result to `TlsSrv.splice` does not relay
application bytes over two TLS connections. It reads and writes raw TLS
records on the upstream descriptor. It also leaves the client's SSL
object and table entry behind when it closes that descriptor. A shared
Bend `Socket` type does not establish shared ownership of TLS state.

The existing `tests/tls_server.sh` covers server TLS to plain TCP splice.
It does not establish support for a bend-kube TLS client as the other end.

## Interface decision needed

Keep the requested use of `N.Tls.open`, and provide a supported transport
bridge before wiring the proxy. The bridge must:

- Keep server certificate verification and kubeconfig `tls-server-name`.
- Use the correct TLS state for each connection.
- Read and write concurrently in both directions without duplicate
  ownership of a socket or concurrent calls on one SSL object.
- Handle TLS read/write readiness and partial writes with bounded buffers.
- Close each SSL object and descriptor once, and clear both registries.
- Preserve bytes already read past an HTTP upgrade response header.
- Work without referring to a dependency's private C symbols.

The preferred next step is a bend-kube transport interface for this
bridge, followed by the corresponding local server adapter. The
bend-kube owner must select and release that interface. An alternative
is to authorize a different upstream TLS implementation in this repo;
that would change the task's explicit `N.Tls.open` requirement.

This is an IO prerequisite. The pure route and response transformations
can be developed separately. They are not implemented by this note.

## Reference behavior to preserve

The relevant source is `pkg/server/filters/{kubelet,metrics,redirect}.go`
and `pkg/authorization/kubeletauthorizer/authorizer.go` at the vcluster
commit above.

- `WithFakeKubelet` prefixes the path with
  `/api/v1/nodes/<node>/proxy`. It does not itself translate kubelet
  exec calls into pod exec calls. The requested pod-subresource routing
  is a vk8s architecture choice.
- `WithRedirect` handles pod log, exec, attach and port-forward before
  the virtual API server. It preserves the query, translates namespace
  and pod name, removes client Authorization, and appends `/` to an
  eight-segment path. That last rule is an upstream quirk.
- Log access through the fake kubelet requires a pod mapping, a live
  virtual pod, and a container in its regular, init or ephemeral
  containers. A host-only injected container must not be exposed.
- Shared-node mode rejects unknown kubelet subpaths. Dedicated-node
  mode forwards them. Health checks pass in both modes.
- Stats rewriting drops unmapped or deleted pods, replaces pod name,
  namespace and UID with virtual values, and drops unmapped PVC volumes.
  It preserves volumes with no PVC reference. An API read error other
  than NotFound is returned, not treated as a missing pod.
- Metrics require tenant filtering too. Forwarding the unmodified host
  metrics response would expose other tenants. `/pods` and
  `/runningpods` return virtual Pod objects after filtering.
- The upstream authorizer uses virtual SubjectAccessReviews. Stats map
  to `get nodes/stats`, metrics to `get nodes/metrics`, and pod lists
  and container logs to `get nodes/proxy`. Other paths use non-resource
  attributes. An allow requires `Allowed && !Denied`. Restricting vk8s
  to the verified kube-apiserver client identity is the narrower option
  permitted by the task; accepting all certificates from the CA is not.
- `WithNodeChanges` handles node update and patch writes. It is separate
  from the fake-kubelet handler. It transfers labels, taints,
  unschedulable and capacity after checking resourceVersion.

## Existing laws and remaining verification

`laws/nodes.bend` already transcribes every case of
`nodes/translate_test.go`, `nodes/syncer_test.go` and
`nodes/fake_syncer_test.go`. Its `nodes.fake_create`,
`nodes.create_backward` and `nodes.update_backward` cases cover the fake
kubelet endpoint in the node fixtures. Preserve these laws.

There are no upstream unit test files for `filters/kubelet.go`,
`filters/metrics.go` or `filters/nodechanges.go` at the pinned commit.
Cases derived from these implementations must be identified as such,
not described as transcriptions of nonexistent unit tests. Other server
tests cover certs, HTTP/2 serving and control-plane metrics; they do not
test the requested kubelet-to-pod route conversion.

After the transport interface is selected, the remaining deliverables
are the pure kubelet module, its concrete and general laws and proofs,
the TLS proxy, serving-cert plan, argv mode, and Linux envtest. No
`laws/done/kubelet` marker is justified yet.

The integration test must use TLS on both sides. It must exercise
`kubectl logs` and `kubectl exec` through the virtual API server, assert
the translated host namespace and pod name, and verify streaming before
EOF. It must also cover failed client authorization, upstream certificate
rejection, upgrade failure, SPDY and WebSocket byte relay, disconnects,
and stats filtering. A plain TCP echo test cannot validate this bridge.
