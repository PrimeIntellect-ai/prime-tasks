isFieldDirty on array of object field
### What happened?

I'm using field array, and I want to check if a specific field is dirty using `isFieldDirty`. It worked properly on basic field, but it's not as I expected when it used on array field.
Here I forked the field array example stackblitz and modify it to use `isFieldDirty`.
So, when I change a field that part of the array field, the dirty flag from the meta is true (work as expected). But the dirty flag from `isFieldDirty('users')` resulted as false, isn't should be true as well? Because the field `users` value has been changed and the dirty flag from meta is true tho
But, when I check the field array to the specific index and field like `isFieldDirty('users[0].name')`, it resulted true. Why when the path is refer to the field array name is not resulted as expected, compared with specific index path?

Or may be is there a function or prop that return the dirty field? For example
`const { dirtyFields } = useForm()`, that will be return the dirty field's name like `{'users'}`

Also i got question for the similar issue with this one on https://github.com/logaretm/vee-validate/issues/3448, related to initialValue that affected from conditional rendering, so the dirty flag is not accurate anymore

### Reproduction steps

Stackblitz link: https://stackblitz.com/edit/vee-validate-v4-array-fields-n33ulm?file=src%2FApp.vue
Step:
1. change user data
2. expected: `isFieldDirty('users')` would be true, actual: it is still false, but the `meta.dirty` of the form is true

### Version

Vue.js 3.x and vee-validate 4.x

### What browsers are you seeing the problem on?

- [ ] Firefox
- [X] Chrome
- [ ] Safari
- [ ] Microsoft Edge

### Relevant log output

_No response_

### Demo link

https://stackblitz.com/edit/vee-validate-v4-array-fields-n33ulm?file=src%2FApp.vue

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](CONDUCT.md)

### Additional contract requirements

- `useForm()` exposes `isFieldTouched(field)`, `isFieldDirty(field)` and `isFieldValid(field)`. Each accepts a field path — a top-level name, a dot-separated nested path, or an indexed array path such as `users[0].name` — and returns a boolean.
- `isFieldTouched(field)` returns `true` when the field itself or any field nested under it has been touched, and `false` when neither the field nor any nested field exists.
- `isFieldDirty(field)` returns `true` when the field itself or any field nested under it is dirty. In particular, after a field inside an array of objects changes (for example `users[0].name`), `isFieldDirty('users')` returns `true`.
- `isFieldValid(field)` returns `true` when the field itself and all fields nested under it are valid, and `false` when any of them is invalid.
