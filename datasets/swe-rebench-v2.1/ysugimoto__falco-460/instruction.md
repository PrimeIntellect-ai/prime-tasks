[Feature] add .prefer_ipv6 field in backend
### Kind of proposals

You can turn on multiple checkboxes.

- [] Parser
- [x] Linter
- [] Simulator
- [] Testing

### Describe the feature

Now Fastly supports IPv6 to origin as `.prefer_ipv6` property in backend declaretion.
We need to support this field in linter in order to suppress UndefinedBackendPropery error.

### Give us your considerations

Support new field of `.prefer_ipv6`
