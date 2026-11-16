Default value declared via SDL may not introspect correctly
> One interesting aspect here is that a default value declared via SDL is coerced twice:
> Once via `valueFromAST` and then again via `coerceInputValueImpl`. Is my reading here correct?
>
> I am not really sure this is a problem, but I wanted to call that out.
>
> _Originally posted by @andimarek in https://github.com/graphql/graphql-js/issues/3049#issuecomment-827036666_

That's a good call out. Coercing more than once should be safe, assuming that `coerce(X) == coerce(serialize(coerce(X)))`

However I think this is likely exposing a real (but maybe low-impact) bug, even before this diff. Default values are exposed via introspection and are not expected to include nested default values:

```graphql
input A {
  a: B = {}
}

input B {
  c: Int = 0
}
```

When introspecting `A.a`, we should see `"defaultValue": "{}"` but if I read correctly likely will see `"defaultValue": "{c:0}"`

If you were to re-print this SDL after introspection, you'd have:

```graphql
input A {
  a: B = { c: 0 }
}
```

which broke the original intent.

Executed results would be correct, however schema representation would be off.

Notably, constructing the schema programmatically would not encounter this bug - only using AST creation would because of how `valueFromAST` works.
