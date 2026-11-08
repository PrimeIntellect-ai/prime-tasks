Template number literal `Cannot read property 'length' of undefined` (glimmer-engine)
Seeing this error when using a raw number literal as an assigned argument property in my template.

```hbs
      <AnimatedText
        @text={{this.errorMessage}}
        @animationDelay={{300}} <-- this is the issue
      />
```

```md
my-app/templates/components/foo.hbs
  -:-  error  Cannot read property 'length' of undefined  undefined
```

`@animationDelay={{300}}` is causing the issue here, removing that line makes the error go away

Here's my `.template-lintrc.js` file

```js
'use strict';

module.exports = {
  extends: 'octane',

  rules: {
    'attribute-indentation': true,
    'inline-link-to': false,
    quotes: 'double',
    'block-indentation': true,
    'img-alt-attributes': true,
    'linebreak-style': true,
    'no-unnecessary-concat': true,
    'self-closing-void-elements': true,
    'no-curly-component-invocation': {
      requireDash: false,
      allow: [
		// ... a bunch of components
      ]
    }
  }
};

```


```
ember-template-lint@^1.1.0:
  version "1.8.1"
ember-cli-template-lint@^1.0.0-beta.3:
  version "1.0.0-beta.3"
```

Let me know if more information is necessary to reproduce.
