Bug: `Proper Ellipsis` rule breaks transcluded links
## Describe the Bug

`Proper Ellipsis` rule breaks transcluded links

## How to Reproduce

``` markdown
![title](a...b.md)

![](c...d.png)
```

Apply `Proper Ellipsis` rule

## Expected Behavior

The note is unchanged

## Actual behavior Behavior

The three consecutive dots `...` were replaced with a single Unicode character `…`, breaking the links

``` markdown
![title](a…b.md)

![](c…d.png)
```
