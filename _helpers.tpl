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
This helper template replaces the placeholder "{javaMemory}" in the dispatch.JavaOptions value
with the computed memory (in Mi) from the "mychart.javaMemory" helper.
It supports both a simple string (folded scalar) and an array of strings.
*/}}
{{- define "mychart.dispatchJavaOptions" -}}
  {{- $javaMemory := include "mychart.javaMemory" . -}}
  {{- $javaOptions := .Values.dispatch.JavaOptions | default "" -}}
  {{- $kind := kindOf $javaOptions -}}
  {{- if eq $kind "slice" -}}
    {{- /* If JavaOptions is an array, iterate and replace in each element */ -}}
    {{- $opts := slice -}}
    {{- range $index, $opt := $javaOptions -}}
      {{- $opts = append $opts (replace "{javaMemory}" $javaMemory $opt) -}}
    {{- end -}}
    {{- join " " $opts -}}
  {{- else -}}
    {{- /* Otherwise, treat it as a simple string */ -}}
    {{- replace "{javaMemory}" $javaMemory $javaOptions -}}
  {{- end -}}
{{- end -}}
