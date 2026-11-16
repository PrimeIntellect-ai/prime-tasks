Am i the first to suggest random order ?
it would be nice if there was a boolean for whether the list show be displayed in order, or in random order.

thanks a lot!

### Additional contract requirements

- The renderer accepts a `random` parameter. When its value is exactly `"true"`, the list of lines is shuffled before rendering; for any other value, or when the parameter is absent, the lines are rendered in the order they were given.
- The rendering model class `RendererModel` exposes a public boolean property `random` that is `true` only when the `random` parameter is exactly `"true"`, and `false` otherwise.
