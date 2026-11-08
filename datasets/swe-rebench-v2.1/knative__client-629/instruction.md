Add support for private KnServices
## In what area(s)?

/kind good-first-issue
/kind feature
/kind proposal

## Describe the feature:

It would be nice if there was a way to specify that a knService should not have an external endpoint.  This means setting the label `serving.knative.dev/visibility: cluster-local`.

### Additional contract requirements

`kn service create` and `kn service update` provide the `--cluster-local` option to request a private Service. When specified, the resulting Knative Service has the label `serving.knative.dev/visibility` set to `cluster-local`.
