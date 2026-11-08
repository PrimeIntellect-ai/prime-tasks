no-top-level-browser-globals rule is flagging types as top level browser globals
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have updated to the latest version of the packages.

### What version of ESLint are you using?

9.27.0

### What version of `eslint-plugin-svelte` are you using?

3.8.0

### What did you do?

```svelte
<script lang="ts">
  let element: HTMLElement;
  let submitHandler: SubmitEvent = (): void => {};
</script>

<form onsubmit={submitHandler}></form>
<div bind:this={element}></div>
```


### What did you expect to happen?

It shouldn't flag types as top level browser globals, because, from my understanding, the objective of this rule is to prevent calling browser specific APIs (e.g. `localStorage`) while in the server.

### What actually happened?

The new `no-top-level-browser-globals` rule is flagging types as top level browser globals.

### Link to **GitHub Repo** with Minimal Reproducible Example

N.A.

### Additional comments

_No response_
