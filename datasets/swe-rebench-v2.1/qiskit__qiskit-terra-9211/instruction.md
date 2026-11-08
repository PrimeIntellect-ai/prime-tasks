Add option in user config file to control `reverse_bits` in `circuit_drawer`
### What should we add?

Currently, the user config file supports `circuit_drawer` display options such as `output` (`"text"`, "`mpl`", etc.). Including the ability to change the `reverse_bits` option would allow users that prefer setting this option to `True` to not have to explicitly set this parameter every time a circuit is drawn.

### Additional contract requirements

The user configuration recognizes `circuit_reverse_bits` as a Boolean setting for the default bit order used when drawing circuits. A malformed value is rejected using the usual user-configuration error behavior. When a drawing call explicitly supplies `reverse_bits`, that value takes precedence over the configured default.
