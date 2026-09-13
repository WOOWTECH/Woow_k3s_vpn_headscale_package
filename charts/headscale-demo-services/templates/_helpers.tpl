{{/*
Helper templates for the headscale-demo-services chart.
*/}}

{{- /*
Target namespace. Falls back to the release namespace so that `-n` ALWAYS
controls object placement: a values-file `namespace.name` that silently beat
`-n` is how a rehearsal once wrote Helm ownership annotations onto a live
production Deployment. Set namespace.name only to place objects somewhere
other than the release namespace, and never in an instance-values file.
*/ -}}
{{- define "headscale-demo-services.ns" -}}
{{ .Values.namespace.name | default .Release.Namespace }}
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
