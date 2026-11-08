PromiseState.refresh should return a new PromiseState
PromiseState.refresh should return a new PromiseState because this way a `shallowEqual` comparison of the props in the wrapped component erroneously returns `true` even though the PromiseState changed
