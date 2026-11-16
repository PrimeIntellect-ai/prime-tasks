Accept slash as <namepath>
spawn from eslint/eslint#1598.

Doctrine rejects the following comments.
```js
/**
 * Base component implementation.
 *
 * @constructor
 * @extends module:stb/emitter~Emitter
 */
```

This is because doctrine doesn't support

* `/` as namepath
*  `@extends <namepath>` syntax
