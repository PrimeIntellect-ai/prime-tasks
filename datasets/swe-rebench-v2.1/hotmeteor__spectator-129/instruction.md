Nested query parameters always fail validation
Query string params such as `?filter[groupId]` always fail validation because retrieving them via `$this->request->query->has` and `$this->request->query->get` doesn't work.

Instead I think the parameter names need to become [HIDDEN]

So that they can be retrieved this way.

This issue should be fixed by: #129

### Additional contract requirements

- The validator must reject a request when a required query parameter with a bracketed name is absent.
- When that bracketed query parameter is submitted, the validator must retrieve its value and validate it against the parameter's declared schema.
