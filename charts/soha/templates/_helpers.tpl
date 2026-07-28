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

{{- define "soha.existingConfig" -}}
{{- $secretName := printf "%s-config" (include "soha.fullname" .) -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- if and $secret (hasKey (default dict $secret.data) "config.yaml") -}}
{{- index $secret.data "config.yaml" | b64dec -}}
{{- else -}}
{}
{{- end -}}
{{- end -}}

{{- define "soha.postgresPassword" -}}
{{- $secretName := printf "%s-config" (include "soha.fullname" .) -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- $secretData := dict -}}
{{- if $secret -}}
{{- $secretData = default dict $secret.data -}}
{{- end -}}
{{- $existing := "" -}}
{{- if hasKey $secretData "postgres-password" -}}
{{- $existing = index $secretData "postgres-password" | b64dec -}}
{{- end -}}
{{- if not $existing -}}
{{- $existing = dig "database" "password" "" (include "soha.existingConfig" . | fromYaml) -}}
{{- end -}}
{{- if and (not .Values.postgres.enabled) (not (trim (default "" .Values.postgres.password))) (not $existing) -}}
{{- fail "postgres.password is required on first install when postgres.enabled=false" -}}
{{- end -}}
{{- include "soha.persistedCredentialValue" (dict "name" "postgres.password" "value" .Values.postgres.password "existing" $existing) -}}
{{- end -}}

{{- define "soha.adminPassword" -}}
{{- $existing := dig "auth" "dev_principal" "password" "" (include "soha.existingConfig" . | fromYaml) -}}
{{- include "soha.persistedCredentialValue" (dict "name" "config.auth.adminPassword" "value" .Values.config.auth.adminPassword "existing" $existing) -}}
{{- end -}}

{{/* Keep the Secret payload and Deployment checksum on one rendered source. */}}
{{- define "soha.appConfig" -}}
app:
  name: soha
http:
  addr: :8080
  base_path: {{ .Values.config.basePath | quote }}
  read_timeout: 15s
  write_timeout: 15s
  idle_timeout: {{ .Values.config.idleTimeout | quote }}
  max_header_bytes: {{ int .Values.config.maxHeaderBytes }}
{{- if .Values.config.trustedProxies }}
  trusted_proxies:
{{- range .Values.config.trustedProxies }}
    - {{ . | quote }}
{{- end }}
{{- else }}
  trusted_proxies: []
{{- end }}
  cors_allowed_origins:
{{- range .Values.config.corsAllowedOrigins }}
    - {{ . | quote }}
{{- end }}
logger:
  level: {{ .Values.config.loggerLevel | quote }}
  format: {{ .Values.config.loggerFormat | quote }}
runtime:
  execution_runner_token: {{ .Values.config.runtime.executionRunnerToken | quote }}
database:
  driver: postgres
  host: {{ include "soha.postgresHost" . | quote }}
  port: {{ .Values.postgres.port }}
  name: {{ .Values.postgres.database | quote }}
  user: {{ .Values.postgres.username | quote }}
  password: {{ include "soha.postgresPassword" . | quote }}
  sslmode: disable
  max_open_conns: 20
  max_idle_conns: 10
  conn_max_lifetime: 1h
  auto_migrate: true
  migration_file: /app/migrations/postgres/0001_init.sql
auth:
  enable_dev_auth: {{ .Values.config.auth.enableDevAuth }}
  dev_principal:
    user_id: {{ .Values.config.auth.adminUserId | quote }}
    name: {{ .Values.config.auth.adminName | quote }}
    email: {{ .Values.config.auth.adminEmail | quote }}
    password: {{ include "soha.adminPassword" . | quote }}
    roles:
{{- range .Values.config.auth.adminRoles }}
      - {{ . | quote }}
{{- end }}
  jwt:
    issuer: {{ .Values.config.auth.jwtIssuer | quote }}
    secret: {{ .Values.config.auth.jwtSecret | quote }}
    access_ttl: {{ .Values.config.auth.accessTTL | quote }}
    refresh_ttl: {{ .Values.config.auth.refreshTTL | quote }}
{{- with .Values.config.auth.oidc }}
  # Deprecated compatibility input. Configure login providers in Settings Center.
  oidc:
    enabled: {{ .enabled }}
    provider_name: {{ .providerName | quote }}
    issuer: {{ .issuer | quote }}
    client_id: {{ .clientId | quote }}
    client_secret: {{ .clientSecret | quote }}
    redirect_url: {{ .redirectUrl | quote }}
    frontend_redirect_url: {{ .frontendRedirectUrl | quote }}
    scopes:
{{- range .scopes }}
      - {{ . | quote }}
{{- end }}
    default_roles:
{{- range .defaultRoles }}
      - {{ . | quote }}
{{- end }}
{{- end }}
monitoring:
  enabled: {{ .Values.config.monitoring.enabled }}
  webhook_token: {{ .Values.config.monitoring.webhookToken | quote }}
swagger:
  enabled: {{ .Values.config.swaggerEnabled }}
  path: /swagger/*any
mcp:
  enabled: {{ .Values.config.mcpEnabled }}
ai_gateway:
  rate_limit:
    backend: {{ .Values.config.aiGateway.rateLimit.backend | quote }}
    redis:
      addr: {{ .Values.config.aiGateway.rateLimit.redis.addr | quote }}
      username: {{ .Values.config.aiGateway.rateLimit.redis.username | quote }}
      password: {{ .Values.config.aiGateway.rateLimit.redis.password | quote }}
      db: {{ .Values.config.aiGateway.rateLimit.redis.db }}
      tls: {{ .Values.config.aiGateway.rateLimit.redis.tls }}
      key_prefix: {{ .Values.config.aiGateway.rateLimit.redis.keyPrefix | quote }}
      timeout: {{ .Values.config.aiGateway.rateLimit.redis.timeout | quote }}
modules:
  delivery:
    enabled: {{ .Values.config.modules.delivery.enabled }}
  monitoring:
    enabled: {{ .Values.config.modules.monitoring.enabled }}
  ai:
    enabled: {{ .Values.config.modules.ai.enabled }}
    features:
      assistant.global: {{ .Values.config.modules.ai.features.globalAssistant }}
  ai_gateway:
    enabled: {{ .Values.config.modules.aiGateway.enabled }}
  virtualization:
    enabled: {{ .Values.config.modules.virtualization.enabled }}
  docker:
    enabled: {{ .Values.config.modules.docker.enabled }}
  security:
    enabled: {{ .Values.config.modules.security.enabled }}
  cmdb:
    enabled: {{ .Values.config.modules.cmdb.enabled }}
security:
  credential_encryption_key: {{ .Values.config.security.credentialEncryptionKey | quote }}
  secret_provider: {{ .Values.config.security.secretProvider | quote }}
bootstrap:
  seed_defaults: {{ .Values.config.seedDefaults }}
kubernetes:
  clusters: []
{{- end -}}

{{- define "soha.appConfigChecksum" -}}
{{- include "soha.appConfig" . | sha256sum -}}
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
