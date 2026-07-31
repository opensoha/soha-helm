{{- define "soha-observability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "soha-observability.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "soha-observability.name" . -}}
{{- end -}}
{{- end -}}

{{- define "soha-observability.labels" -}}
app.kubernetes.io/name: {{ include "soha-observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: opensoha
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "soha-observability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "soha-observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "soha-observability.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "soha-observability.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "soha-observability.lokiEndpoint" -}}
{{- if .Values.collector.destination.endpoint -}}
{{- trimSuffix "/" .Values.collector.destination.endpoint -}}
{{- else -}}
{{- printf "http://%s-loki.%s.svc.cluster.local:3100/otlp" (include "soha-observability.fullname" .) .Release.Namespace -}}
{{- end -}}
{{- end -}}
