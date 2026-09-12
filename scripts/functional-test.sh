#!/usr/bin/env bash
# In-cluster functional test: spins up a userspace Tailscale client pod,
# joins the tenant's tailnet with a freshly-generated key, and confirms it
# reaches every Tailscale proxy's forwarded service by tailnet hostname.
set -euo pipefail

NAMESPACE="${NAMESPACE:-tenant-local}"
RELEASE="${RELEASE:-headscale-tenant}"
CONTEXT="${CONTEXT:-default}"
IMAGE="${IMAGE:-tailscale/tailscale:v1.102.3}"
POD="functest-$$"

cleanup() { kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod "$POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> Reading test device key from secret ${RELEASE}-test-device-preauth-key"
KEY=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get secret "${RELEASE}-test-device-preauth-key" -o jsonpath='{.data.key}' | base64 -d)
[ -n "$KEY" ] || { echo "empty auth key"; exit 1; }

echo "==> Starting client pod $POD (userspace, joins as a real tailnet device)"
kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f - >/dev/null <<PODEOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/component: functional-test
spec:
  restartPolicy: Never
  containers:
    - name: tailscale
      image: $IMAGE
      env:
        - name: TS_AUTHKEY
          value: "$KEY"
        - name: TS_HOSTNAME
          value: "functest"
        - name: TS_USERSPACE
          value: "true"
        - name: TS_EXTRA_ARGS
          value: "--login-server=http://headscale.${NAMESPACE}.svc.cluster.local:8080"
        - name: TS_STATE_DIR
          value: "/tmp/tsstate"
        - name: TS_KUBE_SECRET
          value: ""
      resources:
        requests: {cpu: 20m, memory: 32Mi}
        limits: {cpu: 200m, memory: 128Mi}
PODEOF

echo "==> Waiting for the pod to be Running"
kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=120s

echo "==> Waiting for the tailnet join"
STATE=""
for i in $(seq 1 24); do
  # tailscale's --json output is pretty-printed (space after the colon) —
  # match loosely rather than assuming compact JSON.
  STATE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- tailscale status --json 2>/dev/null | grep -o '"BackendState": *"[A-Za-z]*"' | head -1 || true)
  echo "  [$i] $STATE"
  echo "$STATE" | grep -q '"Running"' && break
  sleep 5
done
echo "$STATE" | grep -q '"Running"' || { echo "tailnet join did not reach Running"; exit 1; }
echo "OK: tailnet online"

fail=0
check() {
  local name="$1" hostname="$2" port="$3" path="${4:-/}"
  echo "==> $name via tailnet ($hostname:$port$path)"
  # No `tailscale curl` in this CLI, and MagicDNS short names aren't
  # guaranteed resolvable from an unprivileged userspace client's own
  # resolver — resolve the peer's tailnet IP from `tailscale status` instead,
  # then speak plain HTTP over `tailscale nc` (a `sleep` after the request
  # keeps stdin open long enough for nc to read the response before exiting).
  local ip
  ip=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- tailscale status --json 2>/dev/null \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d.get('Peer', {}).values():
    if p.get('HostName') == '$hostname':
        print(p['TailscaleIPs'][0]); break
" 2>/dev/null)
  if [ -z "$ip" ]; then
    echo "FAIL: $name — no tailnet peer named $hostname"
    fail=1
    return
  fi
  local resp
  resp=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- sh -c \
    "{ printf 'GET $path HTTP/1.0\r\nHost: $hostname\r\n\r\n'; sleep 2; } | timeout 8 tailscale nc $ip $port" 2>/dev/null || true)
  if echo "$resp" | head -1 | grep -q "^HTTP/1\."; then
    echo "OK: $name reachable ($(echo "$resp" | head -1))"
  else
    echo "FAIL: $name not reachable via tailnet (got: $(echo "$resp" | head -1))"
    fail=1
  fi
}

check nginx  nginx-test    80   /
check ha     homeassistant 8123 /
check odoo   odoo          8069 /web/login

if [ "$fail" -eq 0 ]; then
  echo "FUNCTIONAL TEST OK: tailnet online, all proxies reachable"
else
  echo "FUNCTIONAL TEST FAILED"
  exit 1
fi
