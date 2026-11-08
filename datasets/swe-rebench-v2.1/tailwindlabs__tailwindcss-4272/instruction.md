[JIT] Add support for "raw" purge content
### What version of Tailwind CSS are you using?

v2.1.1

### What build tool (or framework if it abstracts the build tool) are you using?

Maizzle v3.3.1

### What version of Node.js are you using?

v14.15.1

### What browser are you using?

Chrome

### What operating system are you using?

Windows 10

### Reproduction repository

https://github.com/maizzle/maizzle

### Describe your issue

Configuring the `purge` option in your build chain instead of `tailwind.config.js` results in:

```
TypeError: expected path to be a string
```

Sounds like it expects it to be in the `tailwind.config.js` file.

What I'm doing is definining a base config in the file where I compile Tailwind, like this:

```js
const coreConfig = {
  purge: {
    enabled: true,
    content: [
      'src/**/*.*',
    ],
  },
}
```

I then merge that with the config read from my `tailwind.config.js` and use it to compile Tailwind with PostCSS:

```js
// merge() is from lodash
// `tailwindConfigObject` is the contents of `tailwind.config.js`

return postcss([
  tailwindcss(merge(coreConfig, tailwindConfigObject)),
])
  .process(css, {from: undefined})
  .then(result => result.css)
```

The resulting config is correct, and it works fine without JIT.

When I add `mode: 'jit'` in `tailwind.config.js`, it throws the error. As soon as I also add `purge: ['src/**/*.*']` in `tailwind.config.js`, JIT works as expected.

### Additional contract requirements

- In JIT mode, raw purge content is scanned for class candidates, and the corresponding utilities are generated.
- Raw content entries are also accepted in the `content` array of an object-form `purge` configuration.
