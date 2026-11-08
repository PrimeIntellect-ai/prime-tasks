Failed to transform CSS modules with :global in some cases:  .foo:global(.bar).baz {}
### Describe the bug

Currently SWC CSS modules fail to transpile

```css
 .foo:global(.bar).baz {}
```

but do transpile follow ing successfully

```css
 .foo :global(.bar).baz {}
```

You can reproduce this in SWC repo by adding the following code:

![image](https://github.com/swc-project/swc/assets/57202839/6adbeec1-17a6-4473-ab71-2326c79914be)


notice the last item has been stripped


### Input code

```typescript
Input


.foo:global(.bar).baz {}


Output like:

```css
._local_foo.bar {
    color: white;
}
```
```


### Config

_No response_

### Playground link (or link to the minimal reproduction)

https://github.com/swc-project/swc/tree/main/crates/swc_css_modules/tests/fixture/modules/pure

### SWC Info output

_No response_

### Expected behavior

```css
 ._local_foo.bar._local_baz {}
```

### Actual behavior

_No response_

### Version

latest

### Additional context

_No response_

### Additional contract requirements

The graded test harness generates local class names by prefixing the original
name with `__local__` (that is, `new_name_for(local) = "__local__" + local`).
With that configuration the expected transformed output is:

```css
.__local__foo.bar.__local__baz {}
```

for the input `.foo:global(.bar).baz {}`, and

```css
.__local__foo .bar.__local__baz {}
```

for the input `.foo :global(.bar).baz {}`. The `:global(...)` part must be kept
as-is (global), while the local class selectors before and after it are renamed.
