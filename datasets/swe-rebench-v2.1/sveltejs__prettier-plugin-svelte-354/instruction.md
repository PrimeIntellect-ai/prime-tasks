Prettier's `requirePragma` is not respected
Given the file `test.svelte`:

```svelte
<script>
  const foo =        "bar";
</script>

{foo}
```

Prettier won't ignore the file even though the pragma is not present:

```sh
$ npx prettier --require-pragma --check test.svelte
	[warn] test.svelte
    [warn] Code style issues found in the above file. Forgot to run Prettier?
```

See also: https://prettier.io/docs/en/options.html#require-pragma
