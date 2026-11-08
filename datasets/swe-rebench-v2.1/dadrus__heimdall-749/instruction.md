Add endpoint.values equivalent for payload of remote authorizer
### Preflight checklist

- [X] I agree to follow this project's [Code of Conduct](https://github.com/dadrus/heimdall/blob/main/CODE_OF_CONDUCT.md).
- [X] I have read and am following this repository's [Contribution Guidelines](https://github.com/dadrus/heimdall/blob/main/CONTRIBUTING.md)."
- [X] I have discussed this feature request with the community.

### Describe the background of your feature request

Currently, when wanting to change the payload of a `remote` authorizer on a per-pipeline basis, one needs to override the full payload string.
For an authorization API like [OpenFGA's](https://openfga.dev/api/service#/Relationship%20Queries/Check), this means that pipelines have to be defined as follows:
```yaml
- authorizer: openfga
  config:
    payload: |
      {
        "user": "user:{{ .Subject.ID }}",
        "relation": "read",
        "resource": "endpoint:foo"
      }
```
which is error-prone and repetitive.

### Describe your idea

The `remote` authorizer already has a feature that allows substituting values into the URL, like so:
```yaml
- id: foo
  config:
    endpoint:
      url: https://opa.local/v1/data/{{ .Values.namespace }}/{{ .Values.policy }}
      values:
        namespace: myapi/policy
        policy: allow_write
```
where the pipeline can then contain
```yaml
- authorizer: foo
  config:
    endpoint:
      values:
        policy: something_else
```
making it easier to replace parts of the URL without having to fully retype it each time.
I propose a similar mechanism for substituting values into the payload, where the above mentioned `openfga` authorizer could for example be defined as such:
```yaml
- id: openfga
  config:
    endpoint: # etc.
    payload: |
      {
        "user": "user:{{ .Subject.ID }}",
        "relation": {{ quote .Values.relation }},
        "resource": {{ quote .Values.resource }}
      }
    values: # default values
```
and then used in a pipeline like
```yaml
- authorizer: openfga
  config:
    values:
      relation: read
      resource: "endpoint:foo"
```
making it more difficult to accidentally mess up the payload.

### Are there any workarounds or alternatives?

Currently the workaround is what I described in the problem, i.e. always specifying the full payload.

A different way of implementing the solution I mentioned would be to use the same `values` object for both substituting into the URL and into the payload, as I don't really see a reason why they should be separated. In that case I'd remove the `values` key from the `endpoint` object and just have one directly in `config`.

### Version

n/a

### Additional Context

This feature was discussed in this Discord thread: https://discord.com/channels/1100447190796742698/1120438467411857558

### Additional contract requirements

The same payload templating support applies to the `generic` contextualizer: its `payload` template can reference the mechanism's configured `values` (including per-pipeline overrides) through the `Values` object.
