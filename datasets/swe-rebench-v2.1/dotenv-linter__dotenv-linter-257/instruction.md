Add fixer: QuoteCharacterFixer
Implement `trait Fix` to fix warnings caused by `QuoteCharacterChecker`.
And add this `Fix` to the `fixlist` in [fixes.rs](https://github.com/dotenv-linter/dotenv-linter/blob/cf176993360215596c079873725f4a4b7a48f5b0/src/fixes.rs#L32)

```env
# .env

# Wrong
FOO="BAR"

# Correct (After running `QuoteCharacterFixer` it should look like this)
FOO=BAR
```

Implementation example: [LowercaseKeyFixer](https://github.com/dotenv-linter/dotenv-linter/blob/master/src/fixes/lowercase_key.rs)

### Additional contract requirements

- The QuoteCharacterChecker warning message must be exactly `The value has quote characters (', ")`.
- The fixer removes every quote character (`'` and `"`) from the value, so `FOO='B"AR'` becomes `FOO=BAR`.
