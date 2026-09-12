{{/*
Helper templates for the headscale-tenant chart.
*/}}

{{- define "headscale-tenant.ns" -}}
{{ .Values.namespace.name }}
{{- end -}}

{{- define "headscale-tenant.partOf" -}}
app.kubernetes.io/part-of: headscale-tenant
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* `annotations:` block with the keep policy, or nothing. */}}
{{- define "headscale-tenant.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}

{{- define "headscale-tenant.headscaleSvc" -}}
{{ .Values.headscale.name }}.{{ include "headscale-tenant.ns" . }}.svc.cluster.local
{{- end -}}

{{/* Per-proxy state Secret name: unique per proxy so no two proxies can collide. */}}
{{- define "headscale-tenant.proxyStateSecret" -}}
{{- $release := index . 0 -}}
{{- $proxy := index . 1 -}}
{{ $release.Release.Name }}-tailscale-proxy-{{ $proxy.name }}-state
{{- end -}}

{{- define "headscale-tenant.proxyPreAuthSecret" -}}
{{- $release := index . 0 -}}
{{- $proxy := index . 1 -}}
{{ $release.Release.Name }}-proxy-{{ $proxy.name }}-preauth-key
{{- end -}}

{{- define "headscale-tenant.proxySA" -}}
{{- $release := index . 0 -}}
{{- $proxy := index . 1 -}}
{{ $release.Release.Name }}-proxy-{{ $proxy.name }}
{{- end -}}
