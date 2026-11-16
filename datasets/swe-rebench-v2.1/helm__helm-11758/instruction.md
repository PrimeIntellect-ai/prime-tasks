Extra newline being added when using "range .Files.Lines <filename>"
Exactly as in #3617. Templates generated with `range .Files.Lines <filename>` pretend like there is an empty line at the end of the file, but there isn't. For example:

paths.list:
```
/api/v1
/api/v2
```
with template
```
{{- range .Files.Lines "paths.list" }}
- path: {{ . }}
  pathType: ImplementationSpecific
{{- end }}
```
produces
```
- path: /api/v1
  pathType: ImplementationSpecific
- path: /api/v2
  pathType: ImplementationSpecific
- path:
  pathType: ImplementationSpecific
```

Output of `helm version`: `version.BuildInfo{Version:"v3.7.2", GitCommit:"663a896f4a815053445eec4153677ddc24a0a361", GitTreeState:"clean", GoVersion:"go1.16.10"}`
