`consistent-selector-style`: Class names used in `class:` directives can't be rewritten
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have updated to the latest version of the packages.

### What version of ESLint are you using?

9

### What version of `eslint-plugin-svelte` are you using?

3.0.2

### What did you do?

```svelte
<div class:myClass={true} />

<style>
  .myClass {}
</style>
```


### What did you expect to happen?

No issue

### What actually happened?

Issue suggesting a rewrite to a type selector

### Link to **GitHub Repo** with Minimal Reproducible Example

N/A, will send PR instead

### Additional comments

_No response_
