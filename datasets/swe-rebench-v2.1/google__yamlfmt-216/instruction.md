0.13.0 on Windows forces yaml file to end lines with CRLF
in 0.13.0 binary for Windows x86_64, even if with `line_ending: lf` specified in `.yamlfmt` (or manually specifying config file), yaml files are replaced with CRLF line endings.

This is not happeing in 0.12.1.

### Additional contract requirements

- A `line_ending` value set under the `formatter` section of the configuration takes precedence over the top-level `line_ending` value.
- When the `formatter` section does not set `line_ending`, the top-level `line_ending` value is used.
- The formatter is selected by the `type` under the `formatter` section: a non-empty type selects the formatter registered under that type, and an empty or absent type selects the default formatter.
- If the configured formatter type is not registered, running the command fails with an error.
