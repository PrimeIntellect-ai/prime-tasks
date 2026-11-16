at-rule-no-redundant triggers incorrectly when some (but not all) selector has "&"
Example input in Sass:
```scss
.foo {
  @at-root .bar,
  &baz {
    a: b;
  }
}

.foo {
  .bar,
  &baz {
    a: b;
  }
}
```
https://sass-lang.com/playground/#eJwzNNRLy89XqOZSUHBILNEtys8vUdBLSizSAQqoJSVWgWUUFBKtFJKsgaxarlouLrgO/AoBMc4WWQ==

The rule for `@at-root` will trigger saying it's redundant and should be removed. This implies both rules have the same output, however that's not correct. So rather than showing the linter error when _any_ selector has `&`, it should happen only when `_every_` selector does.

cc: @pamelalozano16
