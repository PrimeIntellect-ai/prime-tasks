New feature request: "equalsTo" validator
When I validate registration form, I want to validate password confirmation with schema like this:
```js
let model = obey.model({
	/* Unrelated fields omitted */
	password: {
		type: 'string',
		min: 8
	},
	passwordConfirm: {
		type: 'string',
		equalsTo: 'password'
	}
});
```

### Additional contract requirements

- The model schema property that enables this validation is named `equalTo` (as specified in the interface), for example:
```js
passwordConfirm: {
type: 'string',
equalTo: 'password'
}
```
- A model built with `obey.model({ password: { type: 'string', min: 8 }, passwordConfirm: { type: 'string', equalTo: 'password' } })` must reject validation when `passwordConfirm` does not equal `password`, and resolve when they match.
