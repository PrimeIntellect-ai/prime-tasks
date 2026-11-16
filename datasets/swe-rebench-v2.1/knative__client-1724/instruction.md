Add support for providing sink spec in GVR format
<!-- If you need to report a security issue with Knative, send an email to knative-security@googlegroups.com. -->

### Feature request
The user can specify a sink in subscription create and update (`--sink`, `--sink-reply`, `--sink-dead-letter` flags), source create and update(`--sink` flag), and broker create and update (`--dl-sink` flag). Currently, only a few known types are supported as an argument to these flags ("broker", "ksvc", and "channel"). If the user provides any other prefix outside the supported ones, `kn` returns an `unsupported sink prefix` error.
<!-- Please describe the feature request and why you would like to have it -->

### Use case
To use sinks of custom types.
<!-- Please add a concrete use case to demonstrate how such a feature would add value for the user. If you don't have a use case for your feature, please remove this section (however providing a good use case increases the likelihood to be picked up) -->

### UI Example

<!-- If this is about a new command or command line options, please let us know how you would add it to the "kn" UI (in the code block below). If this is not applicable for your feature, delete this section. -->

```
kn source ping create my-ping --schedule "*/2 * * * *" --data '{ value: "hello" }' --sink <apiVersion>:<kind>:<name>:<namespace>
```

<!--
Optional Classifications, remove the '> ' to select:
> /kind good-first-issue
> /kind proposal
> /kind doc
> /kind cleanup
-->

### Additional contract requirements

- A custom GVR sink is specified as `<apiVersion>/<kind>:<name>[:<namespace>]`, for example `sources.knative.dev/v1/pingsource:foo`. The group/version and the kind are separated by `/`, and the kind and the name by `:`.
- The `<kind>` segment may be given in singular or plural form (for example `pingsource` or `pingsources`); both refer to the same resource.
- Resolving such a sink yields a destination that references the resource by its API version, kind, name and namespace (the namespace defaults to the current namespace when omitted).
- If the referenced sink resource does not exist, resolving the sink returns an error.

<!--
Optional Classifications, remove the '> ' to select:
> /kind good-first-issue
> /kind proposal
> /kind doc
> /kind cleanup
-->
