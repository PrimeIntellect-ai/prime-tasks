Give `Option.show_default` higher priority wrt `Context.show_default`
Currently, `Context.show_default` (a global setting) overrides `Option.show_default` (a local setting). This is counterintuitive and limit expressiveness: once `Context.show_default` is set to `True`, it's impossible to disable `show_default` for a specific option.
