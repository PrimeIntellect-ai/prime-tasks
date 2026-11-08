Prettier removes content from script block
When I use this fenced code block snippet in a markdown file and save the file

````markdown
```svelte
<style>
  h1 {
    color: green;
  }

  p {
    font-style: italic;
  }
</style>

<script>
  let role = "developer";
</script>

<h1>Hello, {role}!</h1>

<p>I hope you are having a good day!</p>

```
````

it removes the content of the `<script>` block and changes it to

```
<script 1>

</script>
```

Not sure if this is related to `prettier-plugin-svelte` but it makes it impossible to use fenced code blocks with svelte, one workaround is to use html as code block language instead.
