New rule: Prevent usage of `htmlSafe`
Any thoughts on adding a rule to prevent usage of `htmlSafe`? `htmlSafe`, when not used properly, can be a vector for XSS and in some codebases it's preferred to prevent it.

ember-template-lint has a [similar rule](https://github.com/ember-template-lint/ember-template-lint/blob/master/docs/rule/no-triple-curlies.md) which prevents usage of triple curlies: `{{{test}}}`.

I was thinking we could just test for usages of the following?

```js
import { htmlSafe } from '@ember/string';
```

I'd be happy to put it together if there's interest?

### Additional contract requirements

- The rule must report a named import of `htmlSafe` from `@ember/string` or `@ember/template`, including when the imported binding is locally renamed.
- It must not report unrelated named imports from those packages or an `htmlSafe` import from a different package.
- The rule must be available through the plugin's exported rules under the `no-html-safe` key so consumers can enable it.
