CLI parsing error
In this guide: https://github.com/containous/traefik/edit/v2.0/docs/content/user-guides/crd-acme/index.md

I think there is a mistake, cause the flag `--certificatesresolvers.default.acme.tlschallenge` is missing the `=true` value.

At least in my test server it won´t work without that, I get this error:

`time="2019-09-09T18:21:05Z" level=error msg="Unable to obtain ACME certificate for domains \"my.domain\": cannot get ACME client ACME challenge not specified, please select TLS or HTTP or DNS Challenge" providerName=default.acme routerName=traefik/traefik-c4832920e2dbeca43c rule="Host(`my.domain`)"`

Unless I am missing something, I think this should be updated in the doc.

### Additional contract requirements

Fix boolean (or pointer) flag parsing when the flag is related to a map.

When a flag is supplied without an explicit value (for example `--foo.default.bar.fuu`), and the corresponding configuration entry is a boolean or a pointer type, `flag.Parse` must record the flag with the value `"true"` instead of consuming the next argument or returning an error. This must also hold when the entry is nested inside a map, i.e. when the type key uses the map-name placeholder `<name>` (for example `foo.<name>.bar.fuu`) and the concrete flag uses a real map key (for example `default`) in its place. The returned map must contain the flag's original key (for example `traefik.foo.default.bar.fuu`) mapped to `"true"`.
