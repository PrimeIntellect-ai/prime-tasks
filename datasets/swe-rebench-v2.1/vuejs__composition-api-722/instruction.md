Ref not unwrapping other refs set with `set` on Node
- Clone https://github.com/posva/bug-report-vca
- `yarn`
- `node index.js`

It should log an object `{ old: false, new: true }` but it logs `{ old: false, new: { value: true }}`

There is also an index.html file to show the (expected) behavior on a browser

### Additional contract requirements

- `set(target, key, val)` adds or updates the property `key` on `target` and returns `val`, including when `val` is a Ref.
- After `set` adds a property whose value is a Ref, reading that property after the Ref's value changes yields the updated value, and assigning a new Ref to the property is unwrapped when read back.
