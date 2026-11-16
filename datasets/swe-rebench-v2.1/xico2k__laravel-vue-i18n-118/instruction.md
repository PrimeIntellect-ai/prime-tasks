Support for html in translation strings
Some of my translation strings contain html, but when the strings are displayed the html breaks. This is because the "/" characters are replaced with ".".

Example:

`<div v-html="$t('Hello <strong>:name</strong>!', { name: 'World' })" />`

outputs:

`<div>Hello <strong>World<.strong>!</div>`

Is there a way to circumvent this behavior? (without removing the html from the translations...)

All `/` are replaced with `.`
If a translatable key is not in the source file, then the `wTrans()` will replace all slashes with dots in it.

That's the case when English strings are used as an input to the translation functions with the plan for later to become IDs for their localizations.

**Current behavior:**

```javascript
import { trans } from 'laravel-vue-i18n';

console.assert(trans('Active / Overdue') === 'Active . Overdue'); // true
```

**Expected behavior**

```javascript
import { trans } from 'laravel-vue-i18n';

console.assert(trans('Active / Overdue') === 'Active / Overdue'); // true
```

To overcome this issue, you're forced to create the `en.json` where keys and values are going to be equal however why would you need that file to translate English into English?
