Bug: leading dots in selectors being ignored in `@supports` blocks since last update
### Environment

ESLint version: v9.22.0
@eslint/css version: v0.5.0
Node version: v23.9.0
npm version: v10.9.1
Operating System: win32 10.0.19045


### Which language are you using?

stylesheet

### What did you do?

<details>
<summary>Configuration</summary>

```js
import js from '@eslint/js'
import globals from 'globals'
import css from '@eslint/css'
import html from '@html-eslint/eslint-plugin'
import htmlParser from '@html-eslint/parser'
import importPlugin from 'eslint-plugin-import'
import json from '@eslint/json'
import regexp from 'eslint-plugin-regexp'
import stylisticJS from '@stylistic/eslint-plugin-js'
import yml from 'eslint-plugin-yml'

export default [
    { ignores: ['**/*.min.js', '**/package-lock.json'] },
    {
        files: ['**/*.{js,mjs}'],
        languageOptions: { ecmaVersion: 'latest', sourceType: 'script', globals: { ...globals.browser }},
        plugins: { 'import': importPlugin, 'js-styles': stylisticJS, regexp },
        rules: {
            ...js.configs.recommended.rules,
            ...importPlugin.flatConfigs.recommended.rules,
            ...regexp.configs['flat/recommended'].rules,
            'indent': 'off', 'no-unexpected-multiline': 'off', // allow whitespace anywhere
            'js-styles/no-trailing-spaces': 'error', // ...except at ends of lines
            'js-styles/max-len': ['error', { 'code': 120, // limit lines to 120 chars except if containing...
                'ignoreComments': true, 'ignoreStrings': true, // ...trailing/own-line comments, quoted strings...
                'ignoreTemplateLiterals': true, 'ignoreRegExpLiterals': true }], // ...or template/regex literals
            'js-styles/no-extra-semi': 'error', // disallow unnecessary semicolons
            'quotes': ['error', 'single', { 'allowTemplateLiterals': true }], // enforce single quotes except backticks to avoid escaping quotes
            'key-spacing': ['error', { 'beforeColon': false, 'afterColon': true }], // enforce spacing in object properties
            'comma-dangle': ['error', 'never'], // enforce no trailing commas in arrays or objects
            'no-async-promise-executor': 'off', // allow promise executor functions to be async (to accomodate await lines)
            'no-constant-condition': 'off', // allow constant conditions
            'no-empty': 'off', // allow empty blocks
            'no-inner-declarations': 'off', // allow function declarations anywhere
            'no-useless-escape': 'off', // allow all escape chars cause ESLint sucks at detecting truly useless ones
            'no-unused-vars': ['error', { 'caughtErrors': 'none' }] // allow unused named args in catch blocks
        }
    },
    { files: ['**/*.css'], language: 'css/css', ...css.configs.recommended },
    {
        files: ['**/*.html'], languageOptions: { parser: htmlParser }, plugins: { '@html-eslint': html },
        rules: {
            ...html.configs['flat/recommended'].rules,
            '@html-eslint/require-title': 'off', // allow missing title tags
            '@html-eslint/quotes': 'off', // allow unquoted attrs for compactness
            '@html-eslint/attrs-newline': 'off', // allow multi-attrs in single line
            '@html-eslint/require-img-alt': 'off', // allow img tags w/o alt attributes
            '@html-eslint/element-newline': ['error', { 'skip': ['html'] }] // allow multi-tags in single line
        }
    },
    { files: ['**/*.json'], language: 'json/json', ...json.configs.recommended },
    { files: ['**/*.mjs'], languageOptions: { sourceType: 'module' }},
    { files: ['**/*.{yaml,yml}'], ...yml.configs['flat/standard'][1] }
]
```
</details>

```css
...

/* Non-baseline features */
@supports (overflow: clip) { body { overflow: clip }}
@supports (user-select: none) { body, button, input, select, textarea { user-select: none }}
@supports (cursor: pointer) {
    .highlight:focus, .highlight:hover, .toggle-switch .track, .cjs-span { cursor: pointer }}
```


### What did you expect to happen?

No error on last line just like pre-update

### What actually happened?

![Image](https://github.com/user-attachments/assets/49dbf07d-bfe9-4ee6-821f-ffaf77504b3e)

### Link to Minimal Reproducible Example

https://github.com/adamlui/chatgptevo.com/actions/runs/13912623235/job/38929820287

### Participation

- [ ] I am willing to submit a pull request for this issue.

### Additional comments

The `highlight` it refers to is a class name so is supported in every browser (but even so it's part of `@supports` block so should still not error)
