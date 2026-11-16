Add a `Plugin` abstraction that allows us to reason about plugins with multiple commands
In #152 and #154 especially we add some hacks to check for `forc-client` in order to handle its unique behaviour of providing multiple commands.

In the future, we will likely add more plugins that support multiple commands (e.g. [`forc-edit`](https://github.com/FuelLabs/sway/issues/2369)) and we should use a proper `Plugin` type (rather than just strings) that allows us to reason about this more generally.

### Additional contract requirements

A `Plugin` is a public type (`fuelup::component::Plugin`) with public fields `name: String` and `executables: Vec<String>`, which together retain the plugin's name and every executable it provides. `Plugin::is_main_executable(&self) -> bool` is true only when exactly one executable is present and its name matches the plugin name. This distinction must apply to plugins generally, not only to `forc-client`.
