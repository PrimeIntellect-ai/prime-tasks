fritzctl temperature on/off
Is there a way to turn on/off the thermostats like direct in the Fritz!Box or at the device? In the help it says only: fritzctl temperature [value in °C] [device names] [flags]

### Additional contract requirements

- Add a function `parseTemperature(s string) (float64, error)` in package `cmd` that converts the temperature argument into a `float64`.
- A numeric string (for example `"21.5"`) is converted directly to its numeric value.
- The keyword `on` maps to `127.0` and the keyword `off` maps to `126.5`; both keywords are recognized case-insensitively.
- A string that is neither a valid number nor a recognized keyword yields a non-nil error.

- The temperature command must allow users to turn thermostats on or off by supplying `on` or `off` as the temperature argument.
- The temperature command's help must communicate that `on` and `off` are accepted alternatives to a numeric temperature.
