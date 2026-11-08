Type validation using predicates rather than TypeRep's
Since most type-checking libraries provide convenient ways to get the predicate for a type, this would allow for much greater interoperability with run-time type systems.

With Sanctuary:

``` js
const isInt = allPass([is(Number), x => x % 1 === 0]);

get(isInt, 'x', {x: 0.5}); //-> Nothing
```

With TComb:

``` js
const Int = t.refinement(t.Number, x => x % 1 === 0, 'Int');

get(Int.is, 'x', {x: 0.5}); //-> Nothing
```

With Sanctuary Def:

``` js
const Int = $.NullaryType('my/Int', allPass([is(Number), x => x % 1 === 0]));

get(Int.test, 'x', {x: 0.5}); //-> Nothing
```

The possibilities are _endless!_ Another option is to accept Sanctuary Def types, which would make the code a little more concise, but the possibilities slightly less endless.

### Additional contract requirements

Add public functions `get`, `gets`, and `parseJson` in `index.js`, exported as
`S.get`, `S.gets`, and `S.parseJson`.

- `get :: Accessible a => Function -> String -> a -> Maybe c` — takes a unary
  predicate, a property name, and an object; returns `Just(value)` when the
  property exists on the object and the predicate returns `true` for its value,
  and `Nothing` otherwise.
- `gets :: Accessible a => Function -> Array String -> a -> Maybe c` — takes a
  unary predicate, an array of property names, and an object; returns
  `Just(value)` when the full path exists and the predicate returns `true` for
  the terminal value, and `Nothing` otherwise.
- `parseJson :: Function -> String -> Maybe b` — takes a unary predicate and a
  string; returns `Just(value)` when the string parses as JSON and the predicate
  returns `true` for the parsed value, and `Nothing` otherwise.

Each function throws a `TypeError` for invalid arguments. The thrown message
must match exactly, including spacing and the final newline.

`get` with a non-function predicate represented as `[1, 2, 3]`:

```text
Invalid value

get :: Accessible a => Function -> String -> a -> Maybe c
                       ^^^^^^^^
                          1

1)  [1, 2, 3] :: Array Number, Array FiniteNumber, Array NonZeroFiniteNumber, Array Integer, Array ValidNumber

The value at position 1 is not a member of ‘Function’.
```

`get` with a non-string key represented as `[1, 2, 3]`:

```text
Invalid value

get :: Accessible a => Function -> String -> a -> Maybe c
                                   ^^^^^^
                                     1

1)  [1, 2, 3] :: Array Number, Array FiniteNumber, Array NonZeroFiniteNumber, Array Integer, Array ValidNumber

The value at position 1 is not a member of ‘String’.
```

`get` with `null` as the object:

```text
Type-class constraint violation

get :: Accessible a => Function -> String -> a -> Maybe c
       ^^^^^^^^^^^^                          ^
                                             1

1)  null :: Null

‘get’ requires ‘a’ to satisfy the Accessible type-class constraint; the value at position 1 does not.
```

`gets` with a non-function predicate represented as `[1, 2, 3]`:

```text
Invalid value

gets :: Accessible a => Function -> Array String -> a -> Maybe c
                        ^^^^^^^^
                           1

1)  [1, 2, 3] :: Array Number, Array FiniteNumber, Array NonZeroFiniteNumber, Array Integer, Array ValidNumber

The value at position 1 is not a member of ‘Function’.
```

`gets` with `null` as the keys:

```text
Invalid value

gets :: Accessible a => Function -> Array String -> a -> Maybe c
                                    ^^^^^^^^^^^^
                                         1

1)  null :: Null

The value at position 1 is not a member of ‘Array String’.
```

`gets` with `null` as the object:

```text
Type-class constraint violation

gets :: Accessible a => Function -> Array String -> a -> Maybe c
        ^^^^^^^^^^^^                                ^
                                                    1

1)  null :: Null

‘gets’ requires ‘a’ to satisfy the Accessible type-class constraint; the value at position 1 does not.
```

`parseJson` with a non-function predicate represented as `"String"`:

```text
Invalid value

parseJson :: Function -> String -> Maybe b
             ^^^^^^^^
                1

1)  "String" :: String

The value at position 1 is not a member of ‘Function’.
```

`parseJson` with a non-string input represented as `[1, 2, 3]`:

```text
Invalid value

parseJson :: Function -> String -> Maybe b
                         ^^^^^^
                           1

1)  [1, 2, 3] :: Array Number, Array FiniteNumber, Array NonZeroFiniteNumber, Array Integer, Array ValidNumber

The value at position 1 is not a member of ‘String’.
```
