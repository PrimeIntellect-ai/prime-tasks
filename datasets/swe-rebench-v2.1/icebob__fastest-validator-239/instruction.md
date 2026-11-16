bug: TypeError: Cannot convert object to primitive value
**What?**

The string validator is in someway evaluating the objects coming as params and it breaks if it has native prototype references (e.g. toString, toJSON)

**How to reproduce it?**

```js
const Validator = require("fastest-validator");
const v = new Validator();
const schema = {    name: { type: "string" },};
const check = v.compile(schema);

console.log(check({ name: "test"})); // it works, and passes
console.log(check({ name: { "abc": 1 }})); // it works, and rejects
console.log(check({ name: { "toString": 1 }})); // it fails - TypeError: Cannot convert object to primitive value
```

**Environment:**

$ node --version
v12.16.1
macOS Catalina 10.15.16
fastest-validator version: 1.11.0

**Comments:**
I didn't inspect the code deeply, but if you have any suggestions about how to solve it, I will be glad to help!

### Additional contract requirements

When a value supplied to a string field is an object with a non-callable own `toString` property, validation must not throw. It must return a validation failure identifying the field as failing string validation.
