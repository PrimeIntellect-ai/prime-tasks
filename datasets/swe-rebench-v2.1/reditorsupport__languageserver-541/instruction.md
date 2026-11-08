Signature help not show up in if-else branch
Consider the following code:

```r
if (sum()) {

} else if (sum()) {

}
```

In the `if (sum())` branch, the signature help of `sum()` works while it does not work in the `else if (sum())` branch when I type `sum(`.
