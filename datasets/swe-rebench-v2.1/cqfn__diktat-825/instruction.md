For if-statement rule need to properly handle comments
Continuation of #801. In case we have comments in the if-block - they should be properly managed,
For example:
```
if (statement1) {
    // comments
    if (statement2) {
     }
}
```

should be converted to:
```
if (statement1 &&
    // comments
     statement2) {

```

### Additional contract requirements

When nested if statements are collapsed, preserve comments embedded in either condition, as well as comments from the outer if-block. Do not lose or duplicate those comments. Comments from the outer if-block retain their original order between the combined conditions.
