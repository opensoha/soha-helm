{{- define "soha.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "soha.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "soha.name" . -}}
{{- end -}}
{{- end -}}

{{- define "soha.labels" -}}
app.kubernetes.io/name: {{ include "soha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "soha.selectorLabels" -}}
app.kubernetes.io/name: {{ include "soha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "soha.postgresServiceName" -}}
{{- printf "%s-postgres" (include "soha.fullname" .) -}}
{{- end -}}

{{- define "soha.postgresHost" -}}
{{- if .Values.postgres.enabled -}}
{{- include "soha.postgresServiceName" . -}}
{{- else -}}
{{- required "postgres.host is required when postgres.enabled=false" .Values.postgres.host -}}
{{- end -}}
{{- end -}}

{{- define "soha.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{- define "soha.persistedCredentialValue" -}}
{{- $name := .name -}}
{{- $value := trim (default "" .value) -}}
{{- $existing := trim (default "" .existing) -}}
{{- if $existing -}}
{{- $existing -}}
{{- else if $value -}}
{{- $value -}}
{{- else -}}
{{- fail (printf "%s is required" $name) -}}
{{- end -}}
{{- end -}}
