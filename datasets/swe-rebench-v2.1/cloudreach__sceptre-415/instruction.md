`generate-config` command
Within our environment, we are wrapping sceptre withing a custom toolchain. There currently is a command to `generate` or render a cloudformation template.

It will be useful to have a `generate-config` or similar command that renders an environment or stack configuration file with all variables resolved (from vars, environment, etc).

This will allow these configurations to be consumed by other tools (before calling `sceptre create-stack`, etc.) while using sceptre's powerful templating capabilities.

### Additional contract requirements

- The CLI commands must be named `generate-stack-config` and `generate-env-config`.
