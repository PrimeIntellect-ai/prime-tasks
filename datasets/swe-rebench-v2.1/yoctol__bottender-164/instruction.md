context.state should not reference to the initialState when create state
Should deeply clone the `initialState` and assign it to `context.state`.
