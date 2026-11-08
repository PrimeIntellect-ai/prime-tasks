setState discrepancy between preact-render-to-string and react-dom/server
We've noticed a discrepancy in how preact / react server renders a component that looks like this:


```
// Note: this app is set up to SSR only, no CSR
export default function App() {
  const [x, setX] = React.useState(0);
  var foo = undefined;

  React.useMemo(() => {
    foo = "foo";
    setX(1);
  }, []);

  return (
    <>
      <pre>x: {x}</pre>
      <pre>foo: {foo}</pre>
    </>
  );
}
```

Code sandboxes for preact and react to compare the output:

* [preact code example](https://codesandbox.io/s/preact-usememo-setstate-example-mrclje?file=/src/App.js)
* [react code example](https://codesandbox.io/s/react-usememo-setstate-example-v9tzg4?file=/src/App.js)

In preact, it appears as though the `setState` is not called. In react however, we are getting one initial call on `setState` here, and the output is `x: 0` vs. `x: 1`.

This isn't very idiomatic react or preact code so I think we can migrate examples that have this issue, but I was curious about whether this is an intended discrepancy, or if this is a bug.

Maybe this is a similar issue to what was raised in https://github.com/preactjs/preact-render-to-string/issues/108 , but with a functional component instead of a class component.

Interested to hear what you think anyway!

### Additional contract requirements

When a function component updates hook state during rendering, server-rendered output must reflect the updated state rather than dropping the update.
