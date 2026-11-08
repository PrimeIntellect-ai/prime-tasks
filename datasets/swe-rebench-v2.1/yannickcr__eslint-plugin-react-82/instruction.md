Allow setting jsx pragma value in eslintrc
I'm using `jsxPragma: 'dom'` with my babel config. (so I don't need to manually add that pragma to each file) However, now my `dom` var appears unused, and there doesn't appear to be any config to set this value in the `.eslintrc`.

I'm not using React, but since the jsx pragma itself is supported for what appears to be other non-React users, I'm hoping this can be done. :)

### Additional contract requirements

- The `jsx-uses-react` rule must accept a `pragma` option that identifies the JSX pragma, and treat that identifier's binding as used when JSX appears.
