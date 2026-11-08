Support `tls` option for `kn domain create`
### Feature request

- DomainMapping supports `spec.tls` field by https://github.com/knative/serving/pull/11250.
- I would like to request `kn domain create` supports an option to fill in the `spec.tls` field.

### Use case

- As an Knative user, I would like to create DomainMapping with custom certificate by kn command so that I can generate the DomainMapping by only one command.

### UI Example

`kn domain create` supports `--tls` option. For example, the following command:

```
$ kn domain create hello-example.default.example.org --tls=my-certs --ref=hello-example
```

creates this DomainMapping:

```
apiVersion: serving.knative.dev/v1beta1
kind: DomainMapping
metadata:
  annotations:
  name: hello-example.default.example.org
  namespace: default
spec:
  ref:
    apiVersion: serving.knative.dev/v1
    kind: Service
    name: hello-example
    namespace: default
  tls:
    secretName: my-certs
```

/kind proposal
/cc  @dsimansk
FYI @shinigambit @julz

### Additional contract requirements

- If `--tls` is given an invalid secret name, the error message must include `invalid`, `name`, and `RFC 1123 subdomain`.
