`consistent-selector-style`: False positives with dynamic names in each blocks
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have updated to the latest version of the packages.

### What version of ESLint are you using?

9.26.0

### What version of `eslint-plugin-svelte` are you using?

04ca0d14cbec79a84987c0cee48c62cf4ff98a8f

### What did you do?

```svelte
{#each ["one", "two"] as count}
  <b class={"bold-" + count}>Bold in each</b>
{/each}

<style>
  .bold-one {
    color: red;
  }

  .bold-two {
    color: blue;
  }
</style>
```


### What did you expect to happen?

No error or suggesting to use ID

### What actually happened?

Sufggesting using element type

### Link to **GitHub Repo** with Minimal Reproducible Example

N/A

### Additional comments

Will make a PR
