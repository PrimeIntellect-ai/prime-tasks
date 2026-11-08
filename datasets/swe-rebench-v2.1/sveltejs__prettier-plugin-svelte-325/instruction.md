svelteAllowShorthand: false not working on bindings
Sample code
```html
<h1 bind:innerHTML={innerHTML} contenteditable="true" />
<h1 innerHTML={innerHTML}/>
```

Expected output with `svelteAllowShorthand: false`
```html
<h1 bind:innerHTML={innerHTML} contenteditable="true" />
<h1 innerHTML={innerHTML}/>
```

Real output:
```html
<h1 bind:innerHTML contenteditable="true" />
<h1 innerHTML={innerHTML}/>
```

[Reproduction](https://github.com/Indeedornot/shorthandReprod) made using starting svelte-kit project

look at `src/routes/+page.svelte` and run `npm run format`
