Add support for interfaces
We should be able to define interfaces with strawberry, something like this:

```python

@strawberry.interface
class Node:
    id: strawberry.ID
```

### Additional contract requirements

- Instances of classes decorated with `@strawberry.interface` or `@strawberry.type` must accept positional field values in declaration order, as in `Node("a")` and `Post("a", "abc")`.
- A class decorated with `@strawberry.type` may inherit from a class decorated with `@strawberry.interface`. The resulting GraphQL type must implement that interface and include its fields alongside its own.
