{{- define "single-container.name" -}}
{{- default .Values.name .Chart.Name | lower | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "single-container.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "single-container.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "single-container.labels" -}}
helm.sh/chart: {{ include "single-container.chart" . }}
{{ include "single-container.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{- define "single-container.selectorLabels" -}}
app: {{ include "single-container.name" . }}
app.kubernetes.io/name: {{ include "single-container.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "single-container.serviceAccountName" -}}
{{- if and .Values.serviceAccount .Values.serviceAccount.create }}
{{- default (include "single-container.fullname" .) .Values.serviceAccount.name }}
{{- else if and .Values.serviceAccount .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- "default" }}
{{- end }}
{{- end }}

{{- define "single-container.containerPort" -}}
{{- if and .Values.gateway .Values.gateway.containerPort }}
{{- .Values.gateway.containerPort }}
{{- else }}
{{- .Values.containerPort | default 8080 }}
{{- end }}
{{- end }}

{{- define "single-container.podSecurityContext" -}}
{{- $sc := default (dict) .Values.securityContext }}
runAsNonRoot: {{ if hasKey $sc "runAsNonRoot" }}{{ $sc.runAsNonRoot }}{{ else }}true{{ end }}
runAsUser: {{ $sc.runAsUser | default 65532 }}
runAsGroup: {{ $sc.runAsGroup | default 65532 }}
fsGroup: {{ $sc.fsGroup | default 65532 }}
seccompProfile:
  type: {{ ($sc.seccompProfile).type | default "RuntimeDefault" }}
{{- with (omit $sc "runAsNonRoot" "runAsUser" "runAsGroup" "fsGroup" "seccompProfile") }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{- define "single-container.containerSecurityContext" -}}
{{- $csc := default (dict) .Values.containerSecurityContext }}
allowPrivilegeEscalation: {{ if hasKey $csc "allowPrivilegeEscalation" }}{{ $csc.allowPrivilegeEscalation }}{{ else }}false{{ end }}
readOnlyRootFilesystem: {{ if hasKey $csc "readOnlyRootFilesystem" }}{{ $csc.readOnlyRootFilesystem }}{{ else }}true{{ end }}
capabilities:
  drop:
    {{- if and $csc.capabilities $csc.capabilities.drop }}
    {{- toYaml $csc.capabilities.drop | nindent 4 }}
    {{- else }}
    - ALL
    {{- end }}
  {{- if and $csc.capabilities $csc.capabilities.add }}
  add:
    {{- toYaml $csc.capabilities.add | nindent 4 }}
  {{- end }}
{{- with (omit $csc "allowPrivilegeEscalation" "readOnlyRootFilesystem" "capabilities") }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{- define "single-container.readOnlyRootFilesystem" -}}
{{- $csc := default (dict) .Values.containerSecurityContext }}
{{- if hasKey $csc "readOnlyRootFilesystem" }}{{ $csc.readOnlyRootFilesystem }}{{ else }}true{{ end }}
{{- end }}
