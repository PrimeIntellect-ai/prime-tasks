Set @/whatever import path as not scoped package
Actually imports like these are matching **scopedRegExp** in **isScope** function. In the example below is not a scoped package, is only an alias to **src** folder

```js
import UnitDevice from '@/components/UnitDevice'
```

So my proposal is to change from

```js
[HIDDEN]
```

to this:

```js
[HIDDEN]
```

which i have tested

### Additional contract requirements

- `isScoped(name)` is a public function exported from `src/core/importType.js`. It reports whether `name` is a scoped package name: `@a/abc` and `@a/abc/def` are scoped, while `@/abc` and `@/abc/def` are not. A `null` or `undefined` `name` is treated as falsy.
