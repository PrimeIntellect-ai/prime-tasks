Recursive schema
Hi, trying to validate a recursive schema for f.ex a category tree, but errors during v.compile with "Maximum call stack size exceeded".

```js
describe("Test recursive schema", () => {
	const v = new Validator();

	let schema = {};
	Object.assign(schema, {
		name: { type: "string" },
		subcategories: {
			type: "array",
			optional: true,
			items: { type: "object", props: schema}
		}
	});

	let check = v.compile(schema);

	it("should compile", () => {
		let category = {
			name: "top",
			subcategories: [
				{
					name: "sub1"
				},
				{
					name: "sub2"
				}
			]
		};

		let res = check(category);

		expect(res).toBe(true);
	});
});
```
