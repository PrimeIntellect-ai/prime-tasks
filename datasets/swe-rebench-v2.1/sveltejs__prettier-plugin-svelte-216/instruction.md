`<style></style>` in comment results incorrect output
source:

```svelte
<!-- <style>
.foo {
  background-image: url("x");
}
</style> -->

<style lang="scss">
.foo {
  background-image: url("x");
}

$map: (
  'alpha': 10,
  'beta': 20,
  'gamma': 30
);
</style>

<span>Hi</span>
```

result:

```svelte
<span>Hi</span>

<!-- <style ✂prettier:content✂="Ci5mb28gewogIGJhY2tncm91bmQtaW1hZ2U6IHVybCgieCIpOwp9Cg=="></style> -->
<style lang="scss">
  .foo {
    background-image: url('x');
  }

  $map: (
    'alpha': 10,
    'beta': 20,
    'gamma': 30
  );
</style>
```
