Disable particular rules for template expressions
### Description

Hi,
I'd like to disable some rules for template expressions only - typically rules about typescript. Example:

```svelte
<button onClick={() => {clicked += 1}}>Increment</button> // HERE

<script lang="ts">
function fn() { // HERE
    return 3;
}
</script>
```

With my current configuration, I get the error `Missing return type on function` (`@typescript-eslint/explicit-function-return-type`) on the two lines marked by comments. This is problematic, because I can't use TS in template expressions and therefore I can't add a return type annotation to the first line of my snippet. However, I would still like to have the rule turned on for the second case, where it correctly reports that I forgot to add the return type annotation.

Currently, I found no way of doing this other than manually ignoring all the "false positives" or getting rid of any non-trivial template expressions - I would like to have a way to say to eslint that the rule `@typescript-eslint/explicit-function-return-type` should be turned off for all template expressions, however it should still check `<script />` blocks.

### Additional contract requirements

The public mechanism for the requested behaviour is the existing
`settings.svelte.ignoreWarnings` setting. It is an array of strings; each string
is either a rule name (for example
`"@typescript-eslint/explicit-function-return-type"`) or a regular-expression
string (for example `"/^space/"`).

- A rule that matches an entry of `settings.svelte.ignoreWarnings` must not be
  reported for any template expression, including template expressions that
  appear after a `<script>` block.
- Such a rule must still be reported inside `<script>` blocks.
- A rule that does not match any entry must still be reported in template
  expressions.
