Binding syntax
If you evaluate the following JSONata expression, you get what I would argue is an unintuitive result:

```
($a := [1,2]; $a[1]=3; $a;)
```

One might expect the answer to be `[1,3]`.  Or at least that if you evaluate:

```
($a := [1,2]; $a[1]=3; $a[1];)
```

you would expect to get `3`.

It seems to me that the middle statement in both blocks should either be a syntax error (LHS must be a pure variable expression) or at least a semantic error (binding to non-variable expressions is not allowed).  But this doesn't trigger either.  Clearly, the middle statement doesn't seem to be having any effect since the answer remains `[1,2]`.  To be honest, I haven't dug deeply enough into this to know exactly what effect the middle statement is having, but it seems to me this is irrelevant since the bigger question is how should that statement be evaluated?

Personally, I think it should be an error.  It seems reasonably easy to detect.

Comments?

### Additional contract requirements

- When the left side of `:=` is not a variable name, the expression must fail with error code `S0212`.
