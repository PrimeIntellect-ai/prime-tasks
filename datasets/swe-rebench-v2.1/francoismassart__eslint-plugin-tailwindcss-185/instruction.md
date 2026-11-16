[Feature request] Lint values in a object
**Is your feature request related to a problem? Please describe.**
Can't lint values in an object passed to a callee.

My list of callees: `["clsx", "cva"]`.

This doesn't work:

```js
const buttons = cva({
  variants: {
    variant: {
      primary: "bg-white text-black font-bold px-4",
      secondary: "bg-black text-white font-semibold px-5",
    },
  },
});
```

This does:

```js
const buttons = cva({
  variants: {
    variant: {
      primary: clsx("bg-white text-black font-bold px-4"),
      secondary: clsx("bg-black text-white font-semibold px-5"),
    },
  },
});
```

**Describe the solution you'd like**
I would like for the first example to work.

### Additional contract requirements

- The `callees` option is an array of function names available in the configuration of the `classnames-order`, `enforces-shorthand`, `no-arbitrary-value`, `no-contradicting-classname`, and `no-custom-classname` rules. Each listed name identifies a function whose first argument is parsed as Tailwind class names.
- For a listed callee called with an object argument, the class names written as direct string property values and as arrays of strings inside that object are linted.
