Uncaught error on Node.js 18.7: `Cannot mix BigInt and other types, use explicit conversions`
My tests using mock-fs are failing with an unhandled error since upgrading from Node.js 18.6 to 18.7:
```
TypeError: Cannot mix BigInt and other types, use explicit conversions
 ❯ FSReqCallback.oncomplete node:fs:212:13
 ❯ node_modules/mock-fs/lib/binding.js:74:9
```
I've narrowed it down to (probably) being a `restore()` call. To reproduce:

1. Install Node.js 18.7
2. clone https://github.com/AlCalzone/jsonl-db
3. `git checkout 8407b733092e32bf5fb56337c59208665eab32e1`
4. `npm run test:ts`
