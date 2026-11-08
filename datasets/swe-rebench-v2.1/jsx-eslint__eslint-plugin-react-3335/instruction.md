False positive for react/display-name on function value assignment to identifier starting with `_`
Both this codes are wrongly identified as Components:

```javascript
obj._property = (a) => {
  if (a == null) return null;
  return f(a);
};
```
```javascript
_variable = (a) => {
  if (a == null) return null;
  return f(a);
};
```
Apparently because words starting with `_` are claimed as starting with a capital letter.
