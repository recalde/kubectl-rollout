{{/*
This helper template converts resources.limits.memory from values.yaml
to an integer value in Mi. For example, "12Gi" becomes "12288" (12 * 1024)
and "500Mi" becomes "500".
*/}}
{{- define "mychart.javaMemory" -}}
{{- $mem := .Values.resources.limits.memory | default "512Mi" -}}
{{- if contains "Gi" $mem -}}
  {{- mul (trimSuffix "Gi" $mem | int) 1024 -}}
{{- else if contains "Mi" $mem -}}
  {{- trimSuffix "Mi" $mem | int -}}
{{- else -}}
  {{- $mem | int -}}
{{- end -}}
{{- end -}}

{{/*
This helper template replaces the placeholder "{javaMemory}" in
the dispatch.JavaOptions string with the computed Java memory in Mi.
It uses the previously defined "mychart.javaMemory" helper.
*/}}
{{- define "mychart.dispatchJavaOptions" -}}
  {{- $javaMemory := include "mychart.javaMemory" . -}}
  {{- $javaOptions := .Values.dispatch.JavaOptions | default "" -}}
  {{- $final := replace "{javaMemory}" $javaMemory $javaOptions -}}
  {{- $final -}}
{{- end -}}
