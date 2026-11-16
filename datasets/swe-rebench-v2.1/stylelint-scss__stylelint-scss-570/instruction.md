Rule idea: forbid assignment to namespaced variables
When using a Sass module with `@use`, exported variables are writable currently (except for built-in modules, so you cannot reassign `math.$pi` to a different value).
I started a discussion in https://github.com/sass/sass/issues/3171 about that, as I find that this makes modules harder to use (the whole point of modules was to make it easier to reason about files locally, but we can still be impacted by assignments done anywhere else).

I think it would make sense to have a linter rule forbidding assignment to namespaced variables (which does not cover the case of `@use "some-module" as *` but covers all other cases):

```scss
@use "some-module" as identifier;

identifer.$var: "should be rejected";
```

The idea would be to forbid variable assignments of the form `<identifier>.$<identifier>`

### Additional contract requirements

- The rule is exposed under the identifier `dollar-variable-no-namespaced-assignment`, so it is enabled in a stylelint configuration as `"scss/dollar-variable-no-namespaced-assignment": true`.
- With that configuration, a declaration whose property has the form `<identifier>.$<identifier>` is reported as a violation at the line where it appears.
