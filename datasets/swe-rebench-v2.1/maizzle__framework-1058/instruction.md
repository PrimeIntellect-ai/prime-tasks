Components `folders` config isn't additive contrary to what the docs say
- Maizzle Version: 4.5.0
- Node.js Version: 18.16.0

The documentation for the components `folders` configuration (https://maizzle.com/docs/configuration/components) states that “_The paths you defined will be added to the default folders._” This is not what happens in my experience.

What I did:

1. `npx degit maizzle/maizzle my-project` and `npm i`
2. In `src`, add an `includes` folder with a file named `header.html`.
3. In the `promotional.html` template, add an `<x-header>` tag.
4. In `config.js`, add the following config under `build`:

```js
    components: {
      folders: ['src/includes'],
    },
```
5. `npm run build`

Result:

```
✖ Failed to compile template: promotional.html
⚠ [components] <x-v-fill> could not find v-fill.html in the defined root paths (src/includes, src/layouts, src/templates, src/includes)
```

The components in `src/components/` can no longer be found. I need to manually add all the default folders for it to work properly.

### Additional contract requirements

- The default component folders are `src/components`, `src/layouts`, and `src/templates`.
- Configured `build.components.folders` are added to these defaults, so every default folder remains in the component search path.
- When a component cannot be resolved, the error message lists the defined root paths; the default folders must appear in that list together with any configured folders.
