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
      resources:
        requests: {cpu: 20m, memory: 32Mi}
        limits: {cpu: 200m, memory: 128Mi}
PODEOF

echo "==> Waiting for the pod to be Running"
kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=120s

echo "==> Waiting for the tailnet join"
STATE=""
for i in $(seq 1 24); do
  STATE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- tailscale status --json 2>/dev/null | grep -o '"BackendState":"[A-Za-z]*"' | head -1 || true)
  echo "  [$i] $STATE"
  [ "$STATE" = '"BackendState":"Running"' ] && break
  sleep 5
done
[ "$STATE" = '"BackendState":"Running"' ] || { echo "tailnet join did not reach Running"; exit 1; }
echo "OK: tailnet online"

fail=0
check() {
  local name="$1" url="$2"
  echo "==> curl (via tailscale) $url"
  if kubectl --context "$CONTEXT" -n "$NAMESPACE" exec "$POD" -- tailscale curl --max-time 10 "$url" >/dev/null 2>&1; then
    echo "OK: $name reachable"
  else
    echo "FAIL: $name not reachable via tailnet"
    fail=1
  fi
}

check nginx  "http://nginx-test/"
check ha     "http://homeassistant:8123/"
check odoo   "http://odoo:8069/web/login"

if [ "$fail" -eq 0 ]; then
  echo "FUNCTIONAL TEST OK: tailnet online, all proxies reachable"
else
  echo "FUNCTIONAL TEST FAILED"
  exit 1
fi
