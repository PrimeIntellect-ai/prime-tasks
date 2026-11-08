HTML comment is duplicated on format
This looks to be a very similar issue to #205.

The following works as a minimum repro in Svelte for VS Code v107.10.0

```
<div>
  <!-- this is duplicated on format -->
  <style></style>
</div>
```

But both of the following work as expected

```
<div>
  <!-- this is *not* duplicated on format -->
  <p>Hi</p>
</div>
```

```
<!-- this is *not* duplicated on format -->
<style></style>
```

So it appears to be the combination of the `<style>` tag and nested structure that triggers the bug.
