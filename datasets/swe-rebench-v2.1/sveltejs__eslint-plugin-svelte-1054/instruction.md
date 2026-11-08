Add rule checking for successful style parsing
### Motivation

With the recent edition of a rule that uses the parsed styles (#489), this rule in fact doesn't produce any errors if the styles cannot be parsed (either they're invalid, or `svelte-eslint-parser` cannot parse the used style language)

### Description

I propose a rule that would produce a warning in either of these 2 cases (parse error / unknown language). This would guarantee that rules using styles (currently only `no-unused-class-name`) work correctly. There's also a minor overlap with the `block-lang` rule, but I think this is OK

### Examples

```svelte
<!-- ✓ GOOD -->
<style>
  .class {
    font-weight: bold;
  }
</style>

<style lang="scss">
  .class {
    font-weight: bold;
  }
</style>

<!-- ✗ BAD -->
<style>
  .class
    font-weight: bold;
</style>

<style lang="unknown">
  .class {
    font-weight: bold;
  }
</style>
```


### Additional comments

_No response_

### Additional contract requirements

- Expose the rule under the public name `valid-style-parse` (as `svelte/valid-style-parse`).
