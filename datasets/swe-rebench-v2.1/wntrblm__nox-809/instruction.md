Allow combination of `--no-venv` and `--no-install` to suppress error on `session.install`
### How would this feature be useful?

For normal operation, we configure `nox` sessions to install their (potentially heavy) requirements to simplify dependency management. In CI, we build a container including all dependencies and run the same `nox` sessions within the container to verify that the container built correctly. In this case, the global (container) interpreter is pre-configured with all requirements, so using `--no-venv` is meaningfully faster.

For sessions that call `session.install`, `nox` rightfully throws an error that the global interpreter would be modified. Adding `--no-install` doesn't resolve the error, however, which would be a convenient way of retaining the ability to both have sessions manage their own setup and skip setup when it's not needed.

### Describe the solution you'd like

Suppress error on `session.install` when both `--no-venv` and `--no-install` are provided, since `session.install` will be a no-op with this combination of arguments.

### Describe alternatives you've considered

#167 and #710 could provide other ways to create this same behavior.

Currently, we use an environment variable to skip installation when in CI and prevent an error on `--no-venv`. This works, but isn't ideal.

### Anything else?

Potentially related to #693. I'm happy to dig in and pull together a PR if this feature is desired!
