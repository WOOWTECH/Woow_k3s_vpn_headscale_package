{{/*
Helper templates for the headscale-demo-services chart.
*/}}

{{- define "headscale-demo-services.ns" -}}
{{ .Values.namespace.name }}
{{- end -}}

{{- define "headscale-demo-services.partOf" -}}
app.kubernetes.io/part-of: headscale-demo-services
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "headscale-demo-services.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}
