Add support for non-uniformly typed Maps
At the moment, we don't support `Map<number | string, RegExp>`, because the keys of `Map { 1 => /a/g, "1" => /b/g }` would clash, as both keys serialise to `{ "1": "/a/g" }` / `{ "1": "/b/g" }`.

The same holds true for other key type combinations, of course.

### Additional contract requirements

- A `Map` is serialized as an array of `[key, value]` pairs (a list of pairs). This representation is used for every `Map`, including Maps whose keys are all of the same type, and it is what makes non-uniformly typed keys collision-free. The corresponding type annotation is `'map'`.
- Within that representation, the key of the `i`-th entry is located at path `[i, 0]` and its value at path `[i, 1]`; nested annotations are therefore recorded at those positions (for example, `a.1.0` denotes the key of the second entry of the Map stored at `a`).
