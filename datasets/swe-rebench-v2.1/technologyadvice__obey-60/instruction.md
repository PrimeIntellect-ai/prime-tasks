initData is not updated
When you use `requireIf`, `requireIfNot` or `equalsTo` (soon) then you may find weird issue - first value of referenced fields are not updated.

### Example

```js
let schema = obey.model({
	phone: { type: "string" },
	phoneType: { type: "string", requireIf: "phone" }
});

schema.validate({ phone: "123" }).then(() => {
	console.error('Bad: Form is invalid, you should not see this message')
})
.catch(() => {

	let muchNewSchema = obey.model({
		phone: { type: "string" },
		phoneType: { type: "string", requireIf: "phone" }
	});

	muchNewSchema.validate({}).then(() => {
		console.log('Good: Bug is fixed');
	})
	.catch((e) => {
		console.error('Bad: Form is valid, you should not see this message');
		console.error(e.message);
	})

})
```

Result:

```diff
- Bad: Form is valid, you should not see this message
- phoneType (undefined): Value required because 'phone' exists
```

[HIDDEN]
https://github.com/TechnologyAdvice/obey/blob/master/src/rules.js#L85

### Additional contract requirements

- Each validation invocation must evaluate supported `requireIf` and `requireIfNot` conditions using that invocation’s input, not input retained from an earlier invocation.
