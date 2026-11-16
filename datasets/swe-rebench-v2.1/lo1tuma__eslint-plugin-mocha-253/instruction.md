no-mocha-arrows drops comments in the function head when fixing
All of these comments are dropped when fixing:
```js
it( ( foo /* one */ ) /* two */ => /* three */ { body(); } );
```

This was noticed while porting this rule to eslint-plugin-qunit: https://github.com/platinumazure/eslint-plugin-qunit/pull/88

The fixes there can be easily backported to this plugin.

### Additional contract requirements

- The fixer must produce these exact outputs:
```js
it(async () => { assert(something, false) })
// it(async function() { assert(something, false) })

it(async () => assert(something, false))
// it(async function() { return assert(something, false); })

it(/*one*/async/*two*/(done)/*three*/=>/*four*/assert(something, false))
// it(/*one*/async function/*two*/(done)/*three*//*four*/ { return assert(something, false); })
```
