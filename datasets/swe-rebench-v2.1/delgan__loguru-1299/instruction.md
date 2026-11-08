Support the implementation of https://no-color.org/
It would be awesome to support the detection of the NO_COLOR environment variable and act according to the specification.

### Additional contract requirements

- Colorization is disabled whenever the `NO_COLOR` environment variable is present in the environment, regardless of its value (including an empty string).
- An explicit `colorize` argument passed to `logger.add()` takes precedence over the `NO_COLOR` environment variable.
