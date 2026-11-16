Allow configuration in pyproject.toml under `tool.argiadne-codegen`
First of all, thanks for this great project!

AFAIK, the official spec recommends that additional config for specific tools is tracked within the tools table of the pyproject.toml file (i.e. `tool.argiadne-codegen`) . https://peps.python.org/pep-0518/#tool-table.

While the its more of a nuisance then a real problem, right now my linters are complaining about an unknown key in the file.

If you think its worthwhile to change this, I'd be happy to submit a PR to support either both keys, or change the current behaviour.

### Additional contract requirements

- Configuration is read from the `[tool.ariadne-codegen]` section of `pyproject.toml`. The legacy top-level `[ariadne-codegen]` section remains supported but is deprecated.
- Add a public function `get_section(config_dict: Dict) -> Dict` in module `ariadne_codegen.config`. It returns the Ariadne-codegen settings section body: the body of `tool.ariadne-codegen` when that key is present, otherwise the body of the legacy top-level `ariadne-codegen` key (emitting a `DeprecationWarning` in that case). When neither key is present it raises `MissingConfiguration`.
- `parse_config_dict(config_dict: Dict) -> Settings` in module `ariadne_codegen.config` accepts a single configuration dictionary argument (it no longer takes a separate section-key parameter) and supports both the `[tool.ariadne-codegen]` and the legacy top-level `[ariadne-codegen]` sections. It returns a populated `Settings` instance and raises `MissingConfiguration` when the section or required fields are missing.
