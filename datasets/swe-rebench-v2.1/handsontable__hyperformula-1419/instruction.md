[Bug]: In a specific combination of adding rows, content, and column amount alteration we get `Uncaught Error` from the `DenseStrategy`
### Description

In a specific combination of adding rows, content, and column amount alteration we get `Uncaught Error` from the `DenseStrategy`.

Related Handsontable issues (internal):

- https://github.com/handsontable/dev-handsontable/issues/1854
- https://github.com/handsontable/dev-handsontable/issues/1719

### Case 1
- add an empty row below the last one (call `addRows()` on last index)
- again, add an empty row below the last one  (call `addRows()` on last index)
- add a value in the last row (call `setCellContents()` on the index of the lastly added row)
- add a new column  (call `addColumns()` on any index)

### Case 2
- add an empty row below the last one (call `addRows()` on last index)
- again, add an empty row below the last one  (call `addRows()` on last index)
- add a value in the last row (call `setCellContents()` on the index of the lastly added row)
- remove any column  (call `removeColumns ()` on any index),

### Video or screenshots

Error for column addition

```js
Uncaught TypeError: Cannot read properties of undefined (reading 'splice')
    at DenseStrategy.addColumns (hyperformula.js?v=bfc9e82e:14088:23)
    at AddressMapping.addColumns (hyperformula.js?v=bfc9e82e:11312:18)
    at hyperformula.js?v=bfc9e82e:13184:27
    at EmptyStatistics.measure (hyperformula.js?v=bfc9e82e:10956:20)
    at _DependencyGraph.addColumns (hyperformula.js?v=bfc9e82e:13183:16)
    at Operations.doAddColumns (hyperformula.js?v=bfc9e82e:18737:30)
    at Operations.addColumns (hyperformula.js?v=bfc9e82e:18183:12)
    at CrudOperations.addColumns (hyperformula.js?v=bfc9e82e:19594:21)
    at _HyperFormula.addColumns (hyperformula.js?v=bfc9e82e:23494:26)
    at main.js:45:4
```

Error for column removal

```js
Uncaught TypeError: Cannot read properties of undefined (reading 'splice')
    at DenseStrategy.removeColumns (hyperformula.js?v=dabf68a5:14100:23)
    at AddressMapping.removeColumns (hyperformula.js?v=dabf68a5:11319:18)
    at hyperformula.js?v=dabf68a5:13147:27
    at EmptyStatistics.measure (hyperformula.js?v=dabf68a5:10956:20)
    at _DependencyGraph.removeColumns (hyperformula.js?v=dabf68a5:13146:16)
    at Operations.doRemoveColumns (hyperformula.js?v=dabf68a5:18678:30)
    at Operations.removeColumns (hyperformula.js?v=dabf68a5:18189:35)
    at CrudOperations.removeColumns (hyperformula.js?v=dabf68a5:19602:45)
    at _HyperFormula.removeColumns (hyperformula.js?v=dabf68a5:23567:26)
    at main.js:45:4
```

### Demo

{column addition} https://stackblitz.com/edit/vitejs-vite-w55sez?file=index.html,main.js&terminal=dev ; {column removal} https://stackblitz.com/edit/vitejs-vite-1ssmt8?file=index.html,main.js&terminal=dev

### HyperFormula version

2.7.0

### Your framework

Vanilla JS

### Your environment

Chrome 123, macOS Ventura
