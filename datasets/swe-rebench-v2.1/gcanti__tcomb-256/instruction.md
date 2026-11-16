[HIDDEN]
### Version

3.2.13

### Expected behaviour

Arrays created in `vm` module should behave like normal

### Steps to reproduce

```js
const vm = require('vm');
const result = vm.runInNewContext('[]', { Array });

const t = require('tcomb');
const List = t.list(t.String);

console.log(result instanceof Array); //=> false
console.log(Array.isArray(result)); //=> true
console.log(List(result)); //=> throws

/tmp/e2b618/node_modules/tcomb/lib/fail.js:2
  throw new TypeError('[tcomb] ' + message);
  ^

TypeError: [tcomb] Invalid value [] supplied to Array<String> (expected an array of String)
    at Function.fail (/tmp/e2b618/node_modules/tcomb/lib/fail.js:2:9)
    at assert (/tmp/e2b618/node_modules/tcomb/lib/assert.js:14:12)
    at List (/tmp/e2b618/node_modules/tcomb/lib/list.js:35:7)
    at Object.<anonymous> (/tmp/e2b618/index.js:9:13)
    at Module._compile (module.js:556:32)
    at Object.Module._extensions..js (module.js:565:10)
    at Module.load (module.js:473:32)
    at tryModuleLoad (module.js:432:12)
    at Function.Module._load (module.js:424:3)
    at Module.runMain (module.js:590:10)
```

## Patch

```patch
 lib/isArray.js | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/lib/isArray.js b/lib/isArray.js
index 8897d0b..50087b9 100644
--- a/lib/isArray.js
+++ b/lib/isArray.js
@@ -1,3 +1,3 @@
 module.exports = function isArray(x) {
[HIDDEN]
[HIDDEN]
 };
\ No newline at end of file
--
2.7.4
```

After applying

```js
const vm = require('vm');
const result = vm.runInNewContext('[]', { Array });

const t = require('tcomb');
const List = t.list(t.String);

console.log(result instanceof Array); //=> false
console.log(Array.isArray(result)); //=> true
console.log(List(result)); //=> []
```

---

According to https://github.com/nodejs/node/issues/3425#issuecomment-149013686 `instanceof Array` is an expected behavior and [HIDDEN]

### Additional contract requirements

- Arrays created in a separate `vm` context must be accepted by `t.list` when their elements satisfy the list's declared type. Values that do not satisfy the declared type must continue to be rejected.
