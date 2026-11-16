Spaces between variable name and `:` are not handled
<!--
  Please note: This template is not optional. Please fill in all fields and
  questions otherwise the issue may be closed. Please provide actual technical
  information about errors, if an error has occurred.
-->

* Node Version: 6.11.3
* NPM Version: 3.10.10
* postcss-less Version: 1.1.1

[HIDDEN]
When declaration contains a space between variable name and :,
It makes [HIDDEN].
Test named `parses variables with whitespaces between name and ":"`, merged in #93, reproduces bug.

### LESS

```less
.navbar {
  @borderTopPx : 4px;
  .media {
    i.user {
      margin-top: @borderTopPx + 10px;
    }
  }
}
```

### JavaScript

Prettier/prettier#2925

### Expected Behavior

`@borderTopPx `to be handled like a _variable_.

### Actual Behavior

`@borderTopPx ` not handled like a _variable_.

### How can we reproduce the behavior?

I noticed this bug using [prettier](https://github.com/prettier/prettier) on Less pasted above.
It is described at Prettier/prettier#2925, where @lydell can provide more accurate details about parsing expectations.

Test named `parses variables with whitespaces between name and ":"` reproduces issue.

Thank for the good work

### Additional contract requirements

- Parse LESS variable declarations with whitespace between the variable name and colon as variables. Exclude that whitespace from the variable name and parse the declaration value.
