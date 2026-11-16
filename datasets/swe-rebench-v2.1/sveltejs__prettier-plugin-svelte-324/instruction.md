Can not write recommended #await shorthand
Hello there!

I want to write this, because I only care about the possibility of an error.

```svelte
  {#await goto('/somewhere') catch error}
    {@debug error}
  {/await}
```

But Prettier formats the snippet above returning this.

```svelte
  {#await goto('/somewhere')}{:catch error}
    {@debug error}
  {/await}
```

This needless separation also leaves a warning: `Empty blocksvelte(empty-block)`, because there is nothing between the `#await` block and the `:catch` one.

My prettier config is as such.

```javascript
/**
 * @type {import('prettier').Options}
 */
module.exports = {
  plugins: [require('prettier-plugin-tailwindcss')],
  pluginSearchDirs: ['.'],
  overrides: [{files: '*.svelte', options: {parser: 'svelte'}}],
  tailwindConfig: './tailwind.config.cjs',
  arrowParens: 'always',
  bracketSpacing: false,
  endOfLine: 'lf',
  plugins: [],
  pluginSearchDirs: ['../../'],
  printWidth: 80,
  semi: true,
  singleQuote: true,
  tabWidth: 2,
  trailingComma: 'es5',
  useTabs: false,
  svelteSortOrder: 'options-styles-scripts-markup',
  svelteStrictMode: true,
  svelteBracketNewLine: false,
  svelteAllowShorthand: false,
  svelteIndentScriptAndStyle: true,
};
```

Should I remove strict mode? In any case, shouldn't this be allowed?

Kind regards.
