Support `TypeIs`
Since right now hypothesis does not support `TypeGuard` (it seems like a complex issue), I propose to add the same exact message about `TypeIs` as well.

From our point of view, these types are indentical. The only difference is how `else:` case is handled in type inference / narrowing in static checks.

I will send a PR soon!

### Additional contract requirements

- For this unsupported callable case, the error message must contain the exact phrase `Hypothesis cannot yet construct a strategy for callables which are PEP-647 TypeGuards or PEP-742 TypeIs`.
