Replace underscores for dashs in multi word names
Seems that according to jsonapi spec and ember data jsonapi,

some_thing , should become some-thing.

In the jsonapi.org page, it has the example:
....

```
attributes": {
      "first-name": "Dan",
      "last-name": "Gebhardt",
      "twitter": "dgeb"
    },
```

....

If i manage to learn how to do this, i can do it on the weekend and write some tests.

### Additional contract requirements

When the `:underscore_to_dash` setting in the `:jsonapi` application environment is enabled, JSON:API attribute names containing underscores must be emitted with dashes in place of the underscores.
