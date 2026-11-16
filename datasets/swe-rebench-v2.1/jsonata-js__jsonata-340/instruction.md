"Invalid JSONata expression" error when ~> expression evaluated in parallel
See https://github.com/node-red/node-red/issues/2183 for background context.

If an expression contains a `~>` operator and is evaluated twice in parallel, both executions return an error of:

> Argument 2 of function "lookup" does not match function signature"

```
const jsonata = require("jsonata");

const expr = jsonata("{'1':'goat','2': 'cheese'} ~> $lookup($string(payload))");

expr.evaluate({"payload":1}, {}, function(err,result) {
    console.log("1",err);
    console.log("1",result);
});
expr.evaluate({"payload":2}, {}, function(err,result) {
    console.log("2",err);
    console.log("2",result);
});
```

The error does not occur if:
 - the second evaluation is done from the callback of the first or wrapped in a `setImmediate`.
 - the expression is rewritten to avoid the `~>` operator. For example, the equivalent expression `$lookup({'1': 'goat', '2': 'cheese'}, $string(payload))` works.
