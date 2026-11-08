[bug][svelte/indent] Invalid indentation for children and snippet closing tag
### Before You File a Bug Report Please Confirm You Have Done The Following...

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have updated to the latest version of the packages.

### What version of ESLint are you using?

9.10.0

### What version of `eslint-plugin-svelte` are you using?

2.44.0

### What did you do?

Does not work with any configuration, you can try the following example in the [current docs](https://sveltejs.github.io/eslint-plugin-svelte/rules/indent/).

<details>
<summary>Code example</summary>

Copy the following into the rules docs

```svelte
<script>
  /* eslint svelte/indent: "error" */
  function click() {}
</script>

<!-- ✓ GOOD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
  CLICK ME!
</button>

<!-- ✗ BAD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
{#snippet example()}
<div>Some code</div>
{/snippet}
{#if true}
<div>Some other code</div>
{/if}
</button>
```
</details>

### What did you expect to happen?

To have the indent of the `{/snippet}` and it's content (basically the `div`), be properly indented, as the `if` clause:

<details>
<summary>Expected result</summary>

```svelte
<script>
  /* eslint svelte/indent: "error" */
  function click() {}
</script>

<!-- ✓ GOOD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
  CLICK ME!
</button>

<!-- ✗ BAD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
  {#snippet example()}
    <div>Some code</div>
  {/snippet}
  {#if true}
    <div>Some other code</div>
  {/if}
</button>
```
</details>

### What actually happened?

The `{/snippet}` indent is not correctly updated

<details>
<summary>Results</summary>

```svelte
<script>
  /* eslint svelte/indent: "error" */
  function click() {}
</script>

<!-- ✓ GOOD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
  CLICK ME!
</button>

<!-- ✗ BAD -->
<button
  type="button"
  on:click={click}
  class="my-button primally"
>
  {#snippet example()}
<div>Some code</div>
{/snippet}
  {#if true}
    <div>Some other code</div>
  {/if}
</button>
```
</details>

### Link to **GitHub Repo** with Minimal Reproducible Example

[ESLint playground example](https://eslint-online-playground.netlify.app/#eNq1U0tu2zAQvcqE2SSGJQUFAhSuE7R1iqJoAxfoMsxCkUYuHYoUSMqIIfgUXXTT0/UkHX6c2k6QXTa2OfPem88bD8yaqrhez3TbaYXK5XaF0iGbsKmtjOjcJVcAxQjQSqEcxHQhVE3gCXCGxmjDGYyKPWBWC1veSQSls171FutsVRqbYE2vKie0gkqK6v7kFIYNV9PisSI9jrIM/v75BZ/n8yvIMgpO73rnNOUA3LrDC85SgPmQVpMgdjGEL9IDUi+tJVy7ziIUOiPaUsq154TJZt++zL7C9acjXz+Cduv/ho8fXrP8cGyV6Dp0gA9l20k8OfWbqMXq8oduESpd47TwT66GImEJMRyLBpzpMRT6j9fuJ5oDlmjCctNwbMyiQ3mlVSMW+dKS2YLsNw6WFhqjW7L1fQQVS8vZO65SPrr/XfYLobbI5HcXgllEPMMh86mzxImxbEsNucDBh8CpsSl76eDGT7e0qVWbG6x02yIdXz32qTxP9xpb2uJuOGtk6YodOGe3gTH4DzpAIdFOSJ+NRsUoidAqOBtTe3uByAOQpVr05QLnnb9cIicpgNj/ZG/SRAr2bOhxS8PR6ruyuicNEtaK1h4kOPP3xJn/N7W67iX9DnTOalxdYecHUJVAauax6r5DnkoDo3WJ6gEx/2Ly0LVnobvJ8/wsP8vIJpe/OX/7BHTo6K5e2ARXG7b5B3bRhxo=)

### Additional comments

_No response_
