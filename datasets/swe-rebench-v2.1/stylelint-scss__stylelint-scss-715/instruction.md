`scss/media-feature-value-dollar-variable` false positive for variables in the form of `module.$var` when using sass modules `@use ...`
Hi everyone,

SCSS code:

```scss
@use "./variables";

@media (max-width: variables.$val) {
  a { color: red; }
}
```

stylelintrc config:

```json
{
  "plugins": [
    "stylelint-scss"
  ],
  "rules": {
    "scss/media-feature-value-dollar-variable": "always"
  },
  "customSyntax": "postcss-scss"
}
```

Error:

```text
3:20  ✖  Expected a dollar-variable (e.g. $var) to be used as a media feature value  scss/media-feature-value-dollar-variable
```

I would expect when using sass variables via the module syntax the rule still sees this as using a $ variable.


Minimal repo to reproduce: https://github.com/mbehzad/scss-media-feature-value-dollar-variable-issue

Cheers
