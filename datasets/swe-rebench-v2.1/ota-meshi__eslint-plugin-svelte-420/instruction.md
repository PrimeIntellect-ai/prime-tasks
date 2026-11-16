False positive for svelte-ignore above containing element
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have updated to the latest version of the packages.

### What version of ESLint are you using?

8.36.0

### What version of `eslint-plugin-svelte` are you using?

2.23.0

### What did you do?

<details>
<summary>Configuration</summary>

```javascript
module.exports = {
  root: true,
  extends: [
    'plugin:svelte/recommended',
  ],
};
```
</details>

Slightly modified from https://daisyui.com/components/dropdown/#dropdown-menu:
```svelte
<!-- svelte-ignore a11y-label-has-associated-control a11y-no-noninteractive-tabindex -->
<div class="dropdown">
  <label tabindex="0">Click</label>
  <ul tabindex="0">
  </ul>
</div>
```


### What did you expect to happen?

svelte-ignore respected at that level. Works with eslint-plugin-svelte3

### What actually happened?

```
/tmp/repro-svelte-ignore-container/test.svelte
  1:20  error  svelte-ignore comment is used, but not warned                                                         svelte/no-unused-svelte-ignore
  1:54  error  svelte-ignore comment is used, but not warned                                                         svelte/no-unused-svelte-ignore
  3:3   error  A11y: noninteractive element cannot have nonnegative tabIndex value(a11y-no-noninteractive-tabindex)  svelte/valid-compile
  3:3   error  A11y: A form label must be associated with a control.(a11y-label-has-associated-control)              svelte/valid-compile
  4:3   error  A11y: noninteractive element cannot have nonnegative tabIndex value(a11y-no-noninteractive-tabindex)  svelte/valid-compile

✖ 5 problems (5 errors, 0 warnings)
```

### Link to **GitHub Repo** with Minimal Reproducible Example

https://github.com/polyzen/repro-svelte-ignore-container

### Additional comments

_No response_

### Additional contract requirements

- A `svelte-ignore` comment immediately above a containing element suppresses matching warnings reported anywhere within that element's descendants.
- A `svelte-ignore` comment immediately above an `{#if}`, `{#each}`, `{#key}`, or `{#await}` block suppresses matching warnings throughout the block's descendants, including applicable `{:else}`, `{:then}`, and `{:catch}` branches.
- A `svelte-ignore` comment inside one branch of a control-flow block does not suppress matching warnings in a different branch.
