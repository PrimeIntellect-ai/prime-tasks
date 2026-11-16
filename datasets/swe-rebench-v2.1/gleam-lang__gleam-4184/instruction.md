extract variable does not insert `_` for first arg when extracting from a pipe
```gleam
dict.get(d, key)
|> result.unwrap(0)
```
on the `unwrap` yields
```gleam
  let value = result.unwrap(0)
  dict.get(d, key)
  |> value
```
which does not compile. Should be `value = result.unwrap(_, 0)`.

### Additional contract requirements

Rather than inserting `_` for the piped argument, the fix for the bug above is
to not offer the "Extract variable" code action for a call that is a step of a
pipeline, i.e. a call appearing on the right-hand side of a `|>` (including the
final call of the pipeline). No `let` binding is produced for such a call, so
the non-compiling extraction shown above never happens.
