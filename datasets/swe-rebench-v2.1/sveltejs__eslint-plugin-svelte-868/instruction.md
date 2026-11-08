New rule: `svelte/no-$inspect`
### Motivation

THe motivation is same as [svelte/no-at-debug-tags](https://sveltejs.github.io/eslint-plugin-svelte/rules/no-at-debug-tags/).the

### Description

The `$inspect` should be removed when you no longer need it after you use it for debugging.

### Examples

```svelte
<script>
	let count = $state(0);
	let message = $state('hello');
        <!-- ✗ BAD -->
	$inspect(count, message); // will console.log when `count` or `message` change
</script>

<button onclick={() => count++}>Increment</button>
<input bind:value={message} />
```


### Additional comments

_No response_

### Additional contract requirements

- The rule is named `no-inspect` and is registered under the name `svelte/no-inspect`.
