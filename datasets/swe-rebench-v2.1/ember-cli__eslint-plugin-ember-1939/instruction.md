New rule to lint against referencing `let` variables in `<template>`
```js
// app/components/foo.gjs
let foo = 1;

function increment() {
  foo++;
}

export default <template>{{foo}}</template>;
```

This does not "work" – it doesn't _error_, but it will essentially capture and compile in the value of the `foo` variable at some arbitrary point and never update again. Even if the component is torn down and a new instance is created/rendered, it will probably still hold on to the old value when the template was initially compiled.

So, generally speaking, one should avoid referencing `let` variables from within `<template>` and instead prefer to use `const` bindings to avoid this confusion/foot-gun.

### Additional contract requirements

The new rule must be exposed under the identifier `template-no-let-reference`, implemented as the module `lib/rules/template-no-let-reference.js` (i.e. `require('lib/rules/template-no-let-reference')` resolves to the rule). The rule reports a single error for each reference to a `let`/`var` binding from within `<template>`, whether the reference appears in a mustache expression or as an element name, and reports nothing for references to `const` bindings or for unresolved names.
