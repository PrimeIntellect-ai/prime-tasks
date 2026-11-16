Rule idea: disallow onClick lambdas as last argument in Composable function
This is an internal style guide Google uses when creating Compose APIs, to ensure that people can't write code like this:

```
Button("Text") {
    // Click listener here
}
```

I cant find this to be officially documented anywhere, but I have a screenshot of a slack message I had with Jim Sproch (the inventor of compose guy :D) 4 years ago

![jimsproch](https://github.com/user-attachments/assets/7941aabc-a7a0-4114-ac7e-44020be1426b)

### Additional contract requirements

The rule is exposed as the Detekt check `LambdaParameterEventTrailingCheck` (see `interface.md`) and reports the message `LambdaParameterEventTrailing.EventLambdaIsTrailingLambda`.

A `@Composable` function is flagged when all of the following hold:

- The function emits content (it calls other composables / emits UI). A `@Composable` function that emits no content is not flagged.
- The function declares a `Modifier` parameter. A `@Composable` function without a `Modifier` parameter is not flagged.
- The last (trailing) parameter is a lambda that is not `@Composable`.
- The trailing lambda is required, i.e. it has no default value. Event lambdas with a default value are not flagged.
- The trailing lambda is an event lambda, i.e. its name starts with `on` (for example `onClick`, `onChange`).

When a function is flagged, exactly one error is reported for the trailing parameter, and its message equals `LambdaParameterEventTrailing.EventLambdaIsTrailingLambda`.
