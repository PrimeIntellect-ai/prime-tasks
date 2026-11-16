TS1015: Parameter cannot have question mark and initializer
The question mark should be dropped in conversion:

```
// @flow
function foo(flag?: boolean = true) {};
```

Bad:

```
function foo(flag?: boolean = true) {}
```

The optional flag? type is boolean | undefined but the initializer removes the undefined, leaving:

```
function foo(flag: boolean = true) {}
```

https://flow-to-ts.netlify.com/#code=Ly8gQGZsb3cKZnVuY3Rpb24gZm9vKGZsYWc/OiBib29sZWFuID0gdHJ1ZSkge307&prettier=1&semi=1&singleQuote=0&tabWidth=4&trailingComma=all&bracketSpacing=0&arrowParens=avoid&printWidth=80&inlineUtilityTypes=0
