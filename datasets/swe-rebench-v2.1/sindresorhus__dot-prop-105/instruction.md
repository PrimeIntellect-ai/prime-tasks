deepKeys returns strange result
```deepKeys({ x: 1, y: "1", z: [1], zz: [], o: {}, n: null, u: undefined, nan: NaN })```

returns

```['x', 'y', 'z[0]', 'n', 'u', 'nan']```

Why is it missing `zz` and `o`, for me it is looks as bug
