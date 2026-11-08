Additional param for options.filter() on copy()
At the moment when using `copy()`, the `options.filter()` function receives the source `path` as it's only param. It would be nice to have both the source and destination paths:

```javascript
fs.copy(srcFolder, destFolder, {
  filter: (srcPath, destPath) => {
    return true
  }
}, cb)
```

This would make checking last mod dates much easier.
