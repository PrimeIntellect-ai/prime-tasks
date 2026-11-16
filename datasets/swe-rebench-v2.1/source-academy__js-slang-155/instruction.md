Repeated parameters: forbidden in strict-mode-JS, allowed in Source?
The current playground allows

```
function f(x, x) {
    1;
}
```

I think this should be forbidden, as in strict-mode-JS.
