[Bug]: `simpleCellAddressFromString` crashes when called with non-ASCII character on an unquoted sheet name
### Description

The sheet names with non-ASCII characters must be enclosed in single quotes. But when they aren't `simpleCellAddressFromString` should return `undefined` (as for invalid cell reference). Currently it crashes with error

```
TypeError: Cannot read properties of null (reading '6')
```

Related: https://github.com/handsontable/hyperformula/issues/1313

Originally reported by a user in HOT forum: https://forum.handsontable.com/t/hyperformula-named-expressions-using-japanese-unicode-characters/7126

### Video or screenshots

![image](https://github.com/handsontable/hyperformula/assets/2480086/2dd83d67-4f52-49d2-9441-0cdb00728f60)


### Demo

https://codesandbox.io/s/happy-matan-j298f2?file=/src/data.js

### HyperFormula version

2.6.0

### Your framework

_No response_

### Your environment

Codesandbox
