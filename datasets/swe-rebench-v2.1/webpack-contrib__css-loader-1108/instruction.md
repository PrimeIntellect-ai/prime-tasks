Option for esModule to export named exports instead of default export
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

- Operating System: macOS
- Node Version: 12.13.1
- NPM Version: 6.13.4
- webpack Version: 4.41.4
- css-loader Version: 3.4.0

### Expected Behavior / Situation

When the new `esModule` option is enabled, I hoped that each CSS class name would be exported as a named export:

```css
.foo {color: red}
.bar {color: blue}
```

```js
export const foo = 'abc'
export const bar = 'def'
```

### Actual Behavior / Situation

Instead, an object of class names to hashes is exported as a default export:

```js
export default {foo: 'abc', bar: 'def'}
```

This means that tree-shaking + inlining is very limited. For example, this is able to tree-shake:

```js
import css from './styles.css'
console.log(css.foo)
```

```js
function(e,t,r){"use strict";r.r(t);console.log("foo-3TUTh")}
```

But this is not able to tree-shake or inline:

```js
import css from './styles.css'
function fn() {
  return css.foo
}
console.log(fn)
```

```js
function(e,r,t){"use strict";t.r(r);var n={foo:"foo-3TUTh",bar:"bar-1JkxR"};console.log((function(){return n.foo}))}
```

### Modification Proposal

If `esModule` used named exports, tree-shaking + inlining would always work as expected.

This would significantly reduce bundle size for apps using CSS modules.

### Additional contract requirements

- Add a `modules.namedExport` boolean option that defaults to `false`.
- When `modules.namedExport` is `true` and `esModule` is `true`, each CSS class name is exported as a camel-cased ES-module named export. For example a class `foo-baz` is exported as `export const fooBaz = "..."`. The default export remains available alongside the named exports.
- When `modules.namedExport` is `true` while `esModule` is `false`, the loader reports the error: `` `Options.module.namedExport` cannot be used without `options.esModule` ``.
- For a `:local(.class)` selector with `esModule: true` and `modules.namedExport: true`, compilation reports: `ModuleParseError: Module parse failed: Unexpected keyword 'class' (7:13)`.


- - For a non-boolean `modules.namedExport` value, option validation reports: `options.modules.namedExport should be a boolean.`
- - With the default generated identifier settings, the local `.bar-baz` class in `./es-module/named/base/index.css` is emitted as `jSf5EjnYI1bvqKHBrOPz6`.
