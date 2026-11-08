Wrong `this` value in custom validators
It seems the `this` is not set correctly in the `custom` validators. Before the 1.0 it pointed to the `Validator` instance but since 1.x it's not.

```js
const Validator = require("../index");

const v = new Validator({
    debug: true,
    useNewCustomCheckerFunction: true,
});

const schema = {
    name: { type: "string", min: 3, max: 255, custom(val) {
        console.log("this", this);
        return val;
    } }
};

console.log(v.validate({ name: "John" }, schema));
```

Output

```
this [ [Function: anonymous], [Function: anonymous] ]
true
```
