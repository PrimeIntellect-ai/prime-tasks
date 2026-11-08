prep() fails when text contains brackets, [ ]
The internal `prep()` function fails when we pass it text that contains brackets:

```r
gradethis:::prep("[aeiou]")
```
```
Error in parse(text = x) : <text>:1:1: unexpected '['
1: [
    ^
```

This prevents us from using `grade_code()` with stringr functions, or other cases where the user is likely to supply a regular expression, which can include `[`.
