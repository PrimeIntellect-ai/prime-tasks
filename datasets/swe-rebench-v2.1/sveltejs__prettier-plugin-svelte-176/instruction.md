Empty style and script tags are expanded into three lines
I'm using Svelte with svelte-preprocessor. The following lines:

```html
<script src="./index.ts"></script>

<style src="./index.css"></style>
```

is formatted as:

```html
<script src="./index.ts">

</script>

<style src="./index.css">

</style>
```

My expected output should be the same as first one. Is this some kind of bug?

Thanks!
