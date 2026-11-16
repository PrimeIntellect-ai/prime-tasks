Allow to map directly from JSON string
As it is quite common to have a JSON in string format. It would be helpful for users of the library to map from the string instead of an object. This would reduce their boiler plate code when using JsonMapper together with an HTTP JSON API.

The desired solution should add some convenience methods such as `mapObjectFromString` and `mapArrayFromString` to the `JsonMapperInterface` and it's implementation.

### Additional contract requirements

- `mapObjectFromString` must apply the same mapping behaviour as `mapObject` (for example type casting and any configured middleware), rather than assigning decoded properties directly.
- Each object returned by `mapArrayFromString` must preserve state already present on the supplied prototype.
