Possible to ignore only specific integration?
Hi!

I know it is possible to annotate IngressRoute resource to make switchboard ignore it:
```
metadata:
  annoations:
    switchboard.borchero.com/ignore: "true"
```
But is it possible to only ignore a specific integration? Or only select specific integration(s) for a resource?

Example use case

We have several sites sharing the same main domain, for example:
- www.example.com
- api.example.com
- xyz.example.com

And we are using cert-manager managed wildcard certificate *.example.com. So the certificate resource is managed separately, and when creating an IngressRoute we would specify the appropriate secret, for example, `star-example-com-tls`. Because of this, we would not want switchboard to attempt to manage this and create a new certificate resource using `star-example-com-tls` secret, and if it did, cert-manager would probably fail operating on the resultant certificate resource, because the target `secretName` resource would already exist, tied to a different certificate resource.

At the same time, we would still like the external-dns resources to be created dynamically.

Of course, the whole cert-manager integration can be disabled, but there still might be other IngressRoute resources which are not covered by the wildcard certificate, and for which switchboard could manage the certificate resources. I would imagine that more similar needs would arise if in the future switchboard would add more possible integrations.

### Additional contract requirements

Add a public method `MatchesIntegration(annotations map[string]string, integration string) bool` on the `Selector` type in the `internal/switchboard` package. It reports whether the named integration should run for a resource carrying the given annotations. When the `switchboard.borchero.com/ignore` annotation is present, it returns `false` if its value is `true`, if its value is `all`, or if its value is a comma-separated list of integration names that contains the named integration (whitespace around each list item is ignored); otherwise it returns `true`.
