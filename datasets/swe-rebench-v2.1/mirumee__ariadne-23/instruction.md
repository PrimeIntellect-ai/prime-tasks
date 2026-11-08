Create `resolve_to` utility
Python variables are usually named using the `snake_case`, whereas majority of JS written today uses the `camelCase`. Ariadne will need to provide a way to resolve one to another.

The idea is to create `resolver_for` function taking single `name` argument and returning resolver for specified attr/key name, enabling **explicit** mapping as such:

```
resolvers_map = {
    "User": {
        "lastVisitedOn": resolve_to("last_visited_on")
    }
}
```

Other advantage of having such utility would be arbitrary field names:

```
resolvers_map = {
    "User": {
        "lastVisitedOn": resolve_to("last_visit")
    }
}
```

### Additional contract requirements

- Provide a public `resolve_to(name: str)` utility that returns a field resolver for the named attribute or dictionary key.
