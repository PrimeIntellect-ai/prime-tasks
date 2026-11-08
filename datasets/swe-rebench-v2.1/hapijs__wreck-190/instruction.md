Add "strict" json option
When I call an API that should always return a JSON object, I need an option that can enforce this. The existing `"force"` value does this, but it does not validate the `content-type`.

Essentially `"strict"` should behave as `"smart"` where, instead of returning the raw payload on non-JSON content-types, it returns an error.
