Bad error when passing a non-node as a context item into `path`
Seems like the normal type checking is skipped in that case.

Example:

```xquery
'a'!path()
```

[Playground link](https://xpath.playground.fontoxml.com/?state=H4sIADwI0GcAA21RwWrDMAz9Fc2XbFDSnUsW2L2DbWzQwS5uojRmthVsuSSU%2FvvkZKWHFQx%2BsqSnJ7%2BTctSi2jyu1FEHo%2FcWo9qo01mt1OiswEqu%2BtsDVGzYYj0OmvtysHo6BEq%2BLTvyTFJUNuSq9VI018fknA5T%2FdGbCHI0WNTBG38AJrLQUYDdy3YFu1ehBO1b2L0lDFNZrS%2B9f4OHOKMFg2mfCmwNF%2FUXJWi0hxwBHqWX%2B8xPHrhHmddxljT86x61G2TVK4NuGowRHAWESxa6QE5kO%2FQJzELJNEAwh%2F4274DBaWv8T1E%2Fe5L6APvEvMgRZoscYZKRsdcSCgrAGBlSzLJFx%2Bf79so8o7x6tc4uZE%2FmDxJbCl3cZSfuH%2BS1EQtw5EtOnX8BWxRB5dcBAAA%3D)

Expected:
```
1: 'a'!path()
   ^^^^^^^^^^

Error: XPTY0004 Unable to cast argument of type xs:string to type node()? while calling path
  at <simpleMapExpr>:1:1 - 1:16
```

Actual:

```
1: 'a'!path()
   ^^^^^^^^^^

TypeError: Cannot read properties of undefined (reading 'Ta')
  at <simpleMapExpr>:1:1 - 1:11
```
