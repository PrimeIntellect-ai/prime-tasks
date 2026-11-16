Value as negative integer error
### Environment

* Elixir 1.9.4 (compiled with Erlang/OTP 22)
* absinthe 1.5.0-rc.5

### Expected behavior

After upgrading `absinthe` from `1.4` to `1.5-pre` I can't use negative numbers as `Enum` values anymore.

```
enum :upvote_direction do
  value(:upvote, as: 1)
  value(:downvote, as: -1)
  value(:novote, as: 0)
end
```

Will throw this error:

```
== Compilation error in file lib/schema/types/comment_type.ex ==
** (Absinthe.Schema.Notation.Error) Invalid Enum value for :downvote. Must be a literal term, dynamic values must use `hydrate`
    lib/absinthe/schema/notation.ex:1378: Absinthe.Schema.Notation.handle_enum_value_attrs/2
    lib/absinthe/schema/notation.ex:1398: Absinthe.Schema.Notation.record_value!/3
    expanding macro: Absinthe.Schema.Notation.value/2
    lib/schema/types/comment_type.ex:64: Api.Schema.CommentType (module)
    expanding macro: Absinthe.Schema.Notation.enum/2
    lib/schema/types/comment_type.ex:62: Api.Schema.CommentType (module)
    (elixir) lib/kernel/parallel_compiler.ex:229: anonymous fn/4 in Kernel.ParallelCompiler.spawn_workers/7
```

Just for reference, if I change the `value(:downvote, as: -1)` to `value(:downvote, as: 2)`, it works as expected.

### Proposed solution

[HIDDEN]

[HIDDEN] Didn't run the test to check if it has collateral issues, but I can prepare a PR if you approve this solution:

_lib/absinthe/schema/notation.ex#L1051_
```diff
defmacro value(identifier, raw_attrs \\ []) do
[HIDDEN]
+
  __CALLER__
  |> recordable!(:value, @placement[:value])
[HIDDEN]
end
```

### Additional contract requirements

- Enum values must accept negative integer literals as their `as` backing values and retain those values in enum behavior.
