Unexpected filename when using export with kubernetes recommended labels
I'm trying to use `tanka export` with a `--format` string that references a [Kubernetes common label](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/) `app.kubernetes.io/name`.

I've verified that

```
{{index .metadata.labels "app.kubernetes.io/name"}}
```
is valid and works with golang templates, but from tanka I just get `<no value>`.
