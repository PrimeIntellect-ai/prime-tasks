Bug: `move-math-block-indicators-to-their-own-line` Incorrectly does not recognize `>` in block quotes as own line
## Describe the Bug

When `move-math-block-indicators-to-their-own-line` is enabled, Linter moves `$$math-blocks$$` outside of block quote environments.

## How to Reproduce

Steps to reproduce the behavior:

1. Enable `move-math-block-indicators-to-their-own-line`
2. Create a new Document
3. Write a block quote with math-block, e.g.
``` markdown
> $$math$$

```
4. Lint the file multiple times. After three steps, the process converges to
``` markdown
>
$$
math
$$

```


### First Linting Step
``` markdown
> $$
math
$$

```

### Second Linting Step
``` markdown
>
$$

math

$$

```
### Final Linting Step
``` markdown
>
$$
math
$$

```

The process has now converged, further linting does not change the file.

## Expected Behavior

The minimal example

``` markdown
> $$math$$

```

Should be converted into

``` markdown
> $$
> math
> $$

```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

I only tested on Desktop

- [x] Desktop
- [ ] Mobile

## Additional Context

The issue does not occur with `empty-line-around-math-blocks`.
