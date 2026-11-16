Struct extension of a refinement of a struct does not use the correct displayName
### Version

3.2.21

### Expected behaviour

A struct extension of a refinement of a struct should use the passed displayName

### Actual behaviour

The struct extension uses the right typeName but interpolated into the default Refinement name format.

### Steps to reproduce

1. Define a struct type
1. Define a refinement of the struct type
1. Extend the refinement of the struct type, passing a name
1. See that the passed name is not used as the displayName

```js
const t = require('tcomb');

const Rectangle = t.struct({
  width: t.Number,
  height: t.Number
}, 'Rectangle');

const Square = t.refinement(Rectangle, ({width, height}) => width === height, 'Square');
const Box = t.struct.extend([Rectangle, {depth: t.Number}], 'Box');
const Column = t.struct.extend([Square, {depth: t.Number}], 'Column');
const Cube = t.refinement(Column, ({width, height, depth}) => width === height && width === depth, 'Cube');

console.log(Square.displayName); // Square
console.log(Box.displayName); // Box -> struct extension of struct uses the passed name
console.log(Column.displayName); // {Column | <function1>} -> falls back to getDefaultName of the refinement, but using the right typeName
console.log(Cube.displayName); // Cube

// a simple workaround is to manually set displayName
Column.displayName = 'Column';
console.log(Column.displayName); // Column
```

### Stack trace and console log

No error here, just not using the expected name.

Thanks for tcomb!
