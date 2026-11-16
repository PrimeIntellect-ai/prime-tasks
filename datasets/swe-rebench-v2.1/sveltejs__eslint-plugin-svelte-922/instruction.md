Add rule `no-useless-children-snippet`
### Motivation

Any content inside a component tag becomes the `children` snippet. Thus, If you have a component with a children snippet without parameters, that's unnecessary.

### Description

I'd like to add a rule that bans the `children` snippet if it has no parameters

### Examples

```svelte
<script>
</script>

<!-- ✓ GOOD -->
<Foo>
  {#snippet bar()}
    Hello
  {/snippet}
</Foo>

<Foo>
  {#snippet children(val)}
    Hello {val}
  {/snippet}
</Foo>

<Foo>
  Hello
</Foo>

<!-- ✗ BAD -->
<Foo>
  {#snippet children()}
    Hello
  {/snippet}
</Foo>
```


### Additional comments

_No response_

### Additional contract requirements

- When reporting this violation, use the exact diagnostic message `Found an unnecessary children snippet.`
- Report this diagnostic at the start of the snippet declaration (the `{` in `{#snippet children()}`, column 3 in the failing fixture).
- Register the rule in the exported plugin rule set so it can be enabled using its `svelte/no-useless-children-snippet` rule ID.
