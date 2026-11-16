Confusing warning message for parameters in FSHOnly mode
`parameters` is an IG-only property. When running in FSHOnly mode, a warning is issued when parameters is present. However, because other configuration values are added to the configuration's `parameters` array, a confusing error message can occur in the following situation:
- `config.yaml` does _not_ contain `parameters`
- `config.yaml` contains `copyrightyear` or `releaselabel`

The resulting warning message is: `The FSHOnly property is set to true, so no output specific to IG creation will be generated. The following properties are unused and only relevant for IG creation: parameters.`

### Additional contract requirements

- When these properties are present, the FSHOnly warning's unused-property list must contain `copyrightYear, releaseLabel, template, menu, contained` in that exact order and spelling.
