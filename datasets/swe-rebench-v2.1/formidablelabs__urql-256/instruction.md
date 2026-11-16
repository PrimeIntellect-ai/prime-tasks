useMutation value should be constant
I'm using a useMutation hook in a parent component, and passing the result down to a child component as the only prop. The child component rerenders whenever the parent rerenders. This means that the result value from useMutation keeps changing. It would be better if it were constant so that the child didn't rerender.
`fetching` initially `false`?
All the documentation and code examples suggest if you check that `fetching` is `true` and `error` is falsey then you can assume `data` is not null.

e.x.

```
const YourComponent = () => {
  const [{ fetching, data }] = useQuery({ query: `{ todos { id } }` });
  return fetching ? <Loading /> : <List data={data.todos} />;
};
```

https://github.com/FormidableLabs/urql#quick-start-guide

However, that's not what I'm seeing. `fetching` is initially `false`:

<img width="373" alt="Screenshot 2019-05-31 10 43 54" src="https://user-images.githubusercontent.com/18193/58724387-4903e780-8391-11e9-9e1c-bd17d7610e3b.png">

This happens for both the `Query` component and `useQuery` hook. Unless you explicitly check that `data` is not null then these examples will crash.

Or am I missing something?

Version: 1.0.5

### Additional contract requirements

- `useMutation(query)` returns a tuple `[state, executeMutation]`. When the component rerenders without the query or the client changing, `executeMutation` keeps the same function identity and `state` keeps the same object identity, so the result can be passed to a child component without causing it to rerender.
- During the initial mount, `useQuery` applies its state changes immediately: the state observed during the first render already has `fetching` set to `true`, rather than starting at `false` and updating on a later render.
- During the initial render, the `Query` component likewise passes `fetching: true` to its render-prop child before query data is available.
