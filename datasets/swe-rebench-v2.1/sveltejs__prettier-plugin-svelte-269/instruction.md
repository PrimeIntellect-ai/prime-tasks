No formatting inside #each destructuring
Code inside `#each` destructuring doesn't appear to be formatted. Using

```json
"prettier": "^2.5.0",
"prettier-plugin-svelte": "^2.5.0",
"svelte": "^3.44.2",
```

**Expected after formatting**

```svelte
<script>
  let arr = [{ a: 1 }]
</script>

{#each arr as { a, b = '' }}
  {a}
  {b}
{/each}
```

**Actual**

```svelte
<script>
  let arr = [{a:1}]
</script>

{#each arr as {a,b =''}}
  {a}
  {b}
{/each}
```

### Additional contract requirements

- Also format destructured bindings in `#await` branches, producing `{#await promise then { a, b = '' }}` and `{:then { a, b = '' }}`.
- Default values may themselves be array or object expressions (e.g. `{ a = [1] }`, `{ a = { b: 1 } }`), and nested destructuring patterns such as `{ a: [b = 1] }` are formatted without added parentheses.
