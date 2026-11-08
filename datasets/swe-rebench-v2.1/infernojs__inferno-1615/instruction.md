Passing state with a Router link no longer works with inferno-router `8.0.3`
I also couldn't find any unit tests for state.

Example:

```tsx
<NavLink
  to={{
    pathname: "/create_post",
    search: "",
    key: "",
    hash: "",
    state: {some: "state here"}
  }}
>a link
</NavLink>
```

State ends up as `null`

### Additional contract requirements

When a `Link` or `NavLink` navigates to a location descriptor containing `state`, the resulting history entry must retain that state. This applies whether navigation adds a new entry or replaces the current entry.
