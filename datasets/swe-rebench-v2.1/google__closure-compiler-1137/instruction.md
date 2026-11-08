ERROR - Parse error. cannot use keyword 'type' here.
When I tried to compile my ECMAScript 6 program using the Closure Compiler, I ran into this error.

Here is the smallest reproducible test case:

```
var { type } = { type: 1 };
```

And here is the error message I get:

```
test.js:1: ERROR - Parse error. cannot use keyword 'type' here.
var { type } = { type: 1 };
           ^
```

As far as I know, `type` is not a keyword or reserved word in any version of ECMAScript.

----

In addition, this code compiles perfectly fine:

```
var type = 1;
```

So it seems Closure is only treating `type` as a keyword in certain situations.
