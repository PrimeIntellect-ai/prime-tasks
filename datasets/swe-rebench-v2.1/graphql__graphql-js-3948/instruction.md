Decorated type deeper than introspection query. 4d array
It does not seem like this library supports 4d arrays.

I have this type defined on my server

```graphql
type MultiPolygon {
  type: GeometryType!
  coordinates: [[[[Float!]!]!]!]!
  bbox: [Float!]
}
```

When I try to load the graphql playground I get this error:

```
Uncaught Error: Decorated type deeper than introspection query.
    at m (buildClientSchema.mjs:69)
    at m (buildClientSchema.mjs:82)
    at m (buildClientSchema.mjs:72)
    at m (buildClientSchema.mjs:82)
    at m (buildClientSchema.mjs:72)
    at m (buildClientSchema.mjs:82)
    at m (buildClientSchema.mjs:72)
    at m (buildClientSchema.mjs:82)
    at w (buildClientSchema.mjs:251)
    at keyValMap.mjs:20
```

This error only occurs when I change the coordinates field from 3d to 4d.

I'm wondering if this is a bug that is fixable or is there a workaround?
