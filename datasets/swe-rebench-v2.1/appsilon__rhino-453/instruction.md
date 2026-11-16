Support `shinymanager::secure_app()`
### Motivation

I try to migrate my Shiny app to Rhino which uses the authentication from shinymanager using secure_app and secure_server functions

### Feature description

Currently I cannot use secure_app function on ui as it throws an error '$ operator is invalid for atomic vectors', so it would be helpful to support these functions natively (or writing a note if there is a way to use them even now)

### Implementation ideas

_No response_

### Impact

_No response_

### Comments

_No response_

### Additional contract requirements

- The `rhino` package provides a function `with_head_tags(ui)`.
- `ui` may be a Shiny UI element (a `shiny.tag` or list) or a function that returns a UI.
- When `ui` is not a function, `with_head_tags(ui)` returns a `shiny.tag.list` that contains a `<head>` tag with the application's JavaScript, CSS and favicon resources together with the original UI.
- When `ui` is a function, `with_head_tags(ui)` returns a function whose formal arguments are identical to those of `ui`. Invoking the returned function produces the same `<head>`-wrapped UI as in the non-function case.
- Provide a how-to guide (a package vignette) explaining how to use `shinymanager::secure_app()` with Rhino.
