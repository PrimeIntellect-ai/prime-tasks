helm lint stuck with malformed template object
Hi

<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`:

> version.BuildInfo{Version:"v3.10.0", GitCommit:"ce66412a723e4d89555dc67217607c6579ffcb21", GitTreeState:"clean", GoVersion:"go1.19.1"}

With this template file (notice the space between the first and the second curly brackets):
`{ {- $relname := .Release.Name -}}`

helm lint does not respond whereas helm template throws an error (which is the normal behaviour) :
> Error: YAML parse error on onboarding-ms/templates/secret.yaml: error converting YAML to JSON: yaml: did not find expected node content
Use --debug flag to render out invalid YAML`

### Additional contract requirements

- For this malformed template, `helm lint` must finish with exactly one diagnostic, and its error text must contain `invalid character '{'`.
