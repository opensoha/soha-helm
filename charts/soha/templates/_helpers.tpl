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

{{- define "soha.networkControlName" -}}
{{- printf "%s-network-control" (include "soha.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "soha.ingestName" -}}
{{- printf "%s-ingest" (include "soha.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "soha.ingestPostgresName" -}}
{{- printf "%s-ingest-postgres" (include "soha.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "soha.postgresHost" -}}
{{- if .Values.postgres.enabled -}}
{{- include "soha.postgresServiceName" . -}}
{{- else -}}
{{- required "postgres.host is required when postgres.enabled=false" .Values.postgres.host -}}
{{- end -}}
{{- end -}}

{{- define "soha.persistenceClaimName" -}}
{{- default (printf "%s-data" (include "soha.fullname" .)) .Values.persistence.existingClaim -}}
{{- end -}}

{{- define "soha.image" -}}
{{- $tag := default (printf "v%s" (trimPrefix "v" .Chart.AppVersion)) .Values.image.tag -}}
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

{{- define "soha.ingestPostgresPassword" -}}
{{- $secretName := printf "%s-config" (include "soha.fullname" .) -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- $existing := "" -}}
{{- if and $secret (hasKey (default dict $secret.data) "ingest-postgres-password") -}}
{{- $existing = index $secret.data "ingest-postgres-password" | b64dec -}}
{{- end -}}
{{- include "soha.persistedCredentialValue" (dict "name" "networkRuntime.ingestPostgres.password" "value" .Values.networkRuntime.ingestPostgres.password "existing" $existing) -}}
{{- end -}}

{{- define "soha.adminPassword" -}}
{{- $existing := dig "auth" "dev_principal" "password" "" (include "soha.existingConfig" . | fromYaml) -}}
{{- include "soha.persistedCredentialValue" (dict "name" "config.auth.adminPassword" "value" .Values.config.auth.adminPassword "existing" $existing) -}}
{{- end -}}

{{/* Reuse installation identity across upgrades and replica rollouts. */}}
{{- define "soha.jwtSecret" -}}
{{- $existing := dig "auth" "jwt" "secret" "" (include "soha.existingConfig" . | fromYaml) -}}
{{- include "soha.persistedCredentialValue" (dict "name" "config.auth.jwtSecret" "value" .Values.config.auth.jwtSecret "existing" $existing) -}}
{{- end -}}

{{- define "soha.credentialEncryptionKey" -}}
{{- $existing := dig "security" "credential_encryption_key" "" (include "soha.existingConfig" . | fromYaml) -}}
{{- include "soha.persistedCredentialValue" (dict "name" "config.security.credentialEncryptionKey" "value" .Values.config.security.credentialEncryptionKey "existing" $existing) -}}
{{- end -}}

{{/* Parse the chart's integer ms/s/m/h duration syntax, in seconds. Core treats
     zero as the default; preserve that behavior before checking its bounds. */}}
{{- define "soha.cliDurationSeconds" -}}
{{- $seconds := 0.0 -}}
{{- $units := dict "ms" 0.001 "s" 1.0 "m" 60.0 "h" 3600.0 -}}
{{- range regexFindAll "[0-9]+(ms|s|m|h)" .value -1 -}}
{{- $unit := regexFind "(ms|s|m|h)$" . -}}
{{- $seconds = addf $seconds (mulf (trimSuffix $unit . | float64) (get $units $unit)) -}}
{{- end -}}
{{- if eq $seconds 0.0 -}}{{ .default }}{{- else -}}{{ $seconds }}{{- end -}}
{{- end -}}

{{- define "soha.validateCLIAuth" -}}
{{- $cli := .Values.config.auth.cli -}}
{{- $device := include "soha.cliDurationSeconds" (dict "value" $cli.deviceTTL "default" 300) | float64 -}}
{{- $poll := include "soha.cliDurationSeconds" (dict "value" $cli.pollInterval "default" 5) | float64 -}}
{{- $access := include "soha.cliDurationSeconds" (dict "value" $cli.accessTTL "default" 900) | float64 -}}
{{- $idle := include "soha.cliDurationSeconds" (dict "value" $cli.idleTTL "default" 604800) | float64 -}}
{{- $absolute := include "soha.cliDurationSeconds" (dict "value" $cli.absoluteTTL "default" 2592000) | float64 -}}
{{- if or (lt $device 30.0) (gt $device 600.0) (lt $poll 1.0) (gt $poll 30.0) -}}
{{- fail "CLI device TTL must be 30s..10m and polling interval 1s..30s" -}}
{{- end -}}
{{- if or (lt $access 1.0) (lt $idle $access) (lt $absolute $idle) (gt $absolute 31536000.0) -}}
{{- fail "CLI session TTLs must be finite with access <= idle <= absolute <= 365d" -}}
{{- end -}}
{{- end -}}

{{/* Keep the Secret payload and Deployment checksum on one rendered source. */}}
{{- define "soha.appConfig" -}}
{{- include "soha.validateCLIAuth" . -}}
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
{{- if .Values.proxyProbeProfiles }}
  proxy_probe_profiles:
{{- range .Values.proxyProbeProfiles }}
    - instance_id: {{ .instanceId | quote }}
      profile_id: {{ .profileId | quote }}
{{- end }}
{{- end }}
{{- if .Values.outpostExecutor.enabled }}
  outpost_runtime_executors:
    - executor_id: {{ .Values.outpostExecutor.executorId | quote }}
      token_file: /var/run/soha-outpost-executor/token
  outpost_slots:
{{- range .Values.outpostExecutor.slots }}
    - id: {{ .id | quote }}
      outpost_id: {{ .outpostId | quote }}
      executor_id: {{ .executorId | quote }}
      namespace: {{ .namespace | quote }}
      name: {{ .name | quote }}
      uid: {{ .uid | quote }}
      template_digest: {{ .templateDigest | quote }}
      max_replicas: {{ .maxReplicas }}
      allow_adoption: {{ .allowAdoption }}
      previous_owner_stopped: {{ .previousOwnerStopped }}
{{- end }}
{{- end }}
{{- if .Values.proxyExecutor.enabled }}
  proxy_runtime_executors:
    - executor_id: {{ .Values.proxyExecutor.executorId | quote }}
      token_file: /var/run/soha-proxy-executor/token
  proxy_slots:
{{- range .Values.proxyExecutor.slots }}
    - id: {{ .id | quote }}
      proxy_id: {{ .proxyId | quote }}
      executor_id: {{ .executorId | quote }}
      workload_kind: {{ .workloadKind | quote }}
      namespace: {{ .namespace | quote }}
      name: {{ .name | quote }}
      uid: {{ .uid | quote }}
      template_digest: {{ .templateDigest | quote }}
      max_replicas: {{ .maxReplicas }}
      allow_adoption: {{ .allowAdoption }}
      previous_owner_stopped: {{ .previousOwnerStopped }}
      members:
{{- range .members }}
        - instance_id: {{ .instanceId | quote }}
          runtime_id: {{ .runtimeId | quote }}
          ordinal: {{ .ordinal }}
{{- end }}
      endpoints:
{{- range .endpoints }}
        - endpoint_id: {{ .endpointId | quote }}
          url: {{ .url | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.radiusExecutor.enabled }}
  radius_runtime_executors:
    - executor_id: {{ .Values.radiusExecutor.executorId | quote }}
      token_file: /var/run/soha-radius-executor/token
  radius_slots:
{{- range .Values.radiusExecutor.slots }}
    - id: {{ .id | quote }}
      site_id: {{ .siteId | quote }}
      nas_binding_id: {{ .nasBindingId | quote }}
      nas_id: {{ .nasId | quote }}
      nas_name: {{ .nasName | quote }}
      access_medium: {{ .accessMedium | quote }}
      ssid: {{ .ssid | quote }}
      executor_id: {{ .executorId | quote }}
      namespace: {{ .namespace | quote }}
      name: {{ .name | quote }}
      uid: {{ .uid | quote }}
      workload_kind: {{ .workloadKind | quote }}
      template_digest: {{ .templateDigest | quote }}
      service_account: {{ .serviceAccount | quote }}
      max_replicas: {{ .maxReplicas }}
      members:
{{- range .members }}
        - member_id: {{ .memberId | quote }}
          runtime_id: {{ .runtimeId | quote }}
          ordinal: {{ .ordinal }}
          endpoint: {{ .endpoint | quote }}
          credential_ref: {{ .credentialRef | quote }}
{{- end }}
      configurations:
{{- range .configurations }}
        - reference: {{ .material.reference | quote }}
          tree_hash: {{ .material.treeHash | quote }}
          nas_shared_secret_ref: {{ .material.nasSharedSecretRef | quote }}
          eap_server_certificate_ref: {{ .material.eapServerCertificateRef | quote }}
          eap_server_key_ref: {{ .material.eapServerKeyRef | quote }}
          eap_ca_ref: {{ .material.eapCARef | quote }}
          hooks_attested: {{ .material.hooksAttested }}
          eap_server_trust:
            server_names: {{ .eapServerTrust.serverNames | toJson }}
            ca_certificates: {{ .eapServerTrust.caCertificates | toJson }}
            wifi_security: {{ .eapServerTrust.wifiSecurity | toJson }}
{{- if hasKey .eapServerTrust "eapMethod" }}
            eap_method: {{ .eapServerTrust.eapMethod | toJson }}
{{- end }}
{{- if hasKey .eapServerTrust "innerMethod" }}
            inner_method: {{ .eapServerTrust.innerMethod | toJson }}
{{- end }}
{{- if hasKey .eapServerTrust "credentialSource" }}
            credential_source: {{ .eapServerTrust.credentialSource | toJson }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
database:
  driver: postgres
  host: {{ include "soha.postgresHost" . | quote }}
  port: {{ .Values.postgres.port }}
  name: {{ .Values.postgres.database | quote }}
  user: {{ .Values.postgres.username | quote }}
  password: {{ include "soha.postgresPassword" . | quote }}
  sslmode: {{ .Values.postgres.sslMode | quote }}
  max_open_conns: 20
  max_idle_conns: 10
  conn_max_lifetime: 1h
  auto_migrate: true
  migration_file: /app/migrations/postgres/0001_init.sql
auth:
  cli:
    enabled: {{ .Values.config.auth.cli.enabled }}
    public_url: {{ .Values.config.auth.cli.publicURL | quote }}
    allow_password: {{ .Values.config.auth.cli.allowPassword }}
    device_ttl: {{ .Values.config.auth.cli.deviceTTL | quote }}
    poll_interval: {{ .Values.config.auth.cli.pollInterval | quote }}
    access_ttl: {{ .Values.config.auth.cli.accessTTL | quote }}
    idle_ttl: {{ .Values.config.auth.cli.idleTTL | quote }}
    absolute_ttl: {{ .Values.config.auth.cli.absoluteTTL | quote }}
    create_limit: {{ int .Values.config.auth.cli.createLimit }}
    source_pending_limit: {{ int .Values.config.auth.cli.sourcePendingLimit }}
    active_grant_limit: {{ int .Values.config.auth.cli.activeGrantLimit }}
    source_attempt_limit: {{ int .Values.config.auth.cli.sourceAttemptLimit }}
    user_attempt_limit: {{ int .Values.config.auth.cli.userAttemptLimit }}
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
    secret: {{ include "soha.jwtSecret" . | quote }}
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
{{- if .Values.config.networkIngestQuery.enabled }}
network_ingest_query:
  url: {{ .Values.config.networkIngestQuery.url | quote }}
  ca_file: /run/soha-network-ingest-query/ca.crt
  cert_file: /run/soha-network-ingest-query/tls.crt
  key_file: /run/soha-network-ingest-query/tls.key
  server_name: {{ .Values.config.networkIngestQuery.serverName | quote }}
  timeout: {{ .Values.config.networkIngestQuery.timeout | quote }}
  max_response_bytes: {{ int .Values.config.networkIngestQuery.maxResponseBytes }}
{{- end }}
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
  credential_encryption_key: {{ include "soha.credentialEncryptionKey" . | quote }}
  protected_durable_storage: {{ .Values.config.security.protectedDurableStorage }}
  secret_provider: {{ .Values.config.security.secretProvider | quote }}
{{- if .Values.outpostExecutor.enabled }}
  outpost_signing_key_id: {{ .Values.outpostExecutor.signingKey.keyId | quote }}
  outpost_signing_private_key: "${SOHA_OUTPOST_SIGNING_PRIVATE_KEY}"
{{- end }}
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

{{- define "soha.dshName" -}}
{{- printf "%s-dsh" (include "soha.fullname" . | trunc 59 | trimSuffix "-") -}}
{{- end -}}

{{- define "soha.hindsightName" -}}
{{- printf "%s-hindsight" (include "soha.fullname" . | trunc 53 | trimSuffix "-") -}}
{{- end -}}
