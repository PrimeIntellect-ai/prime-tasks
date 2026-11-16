Add OTEL_PHP_DETECTORS environment variable
Add OTel PHP specific OTEL_PHP_DETECTORS environment variable to set up a given comma-separated list of detectors.

### Additional contract requirements

- Supported detector names are `env`, `host`, `os`, `process`, `process_runtime`, `sdk`, and `sdk_provided`; the value `none` selects no detectors.
