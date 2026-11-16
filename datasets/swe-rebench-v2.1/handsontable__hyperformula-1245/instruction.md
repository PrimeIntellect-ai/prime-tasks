SEARCH: Incorrect results when using `caseSensitive: true` config option
### Description

While adding additional codecov for `SEARCH` the following issues were found when `Hyperformula` is using the `caseSensitive=false` config option
1. The `caseSensitive` option is ignored and always uses a case-insensitive `SEARCH`
2. An incorrect index is being calculated when the pattern is NOT found

These issues can be observed with the following unit test
```
it('bug', () => {
  const engineCaseInsensistive = HyperFormula.buildFromArray(
    [
      ['=SEARCH(".B", "fooBarBaz")'],
      ['=SEARCH(".B", "fooBarBaz", 5)'],
      ['=SEARCH(".b", "fooBarBaz")'],
      ['=SEARCH(".b", "fooBarBaz", 5)'],
    ],
    {useRegularExpressions: true, caseSensitive: false}
  )
  expect(engineCaseInsensistive.getCellValue(adr('A1'))).toEqual(3)
  expect(engineCaseInsensistive.getCellValue(adr('A2'))).toEqual(6)
  expect(engineCaseInsensistive.getCellValue(adr('A3'))).toEqual(3)
  expect(engineCaseInsensistive.getCellValue(adr('A4'))).toEqual(6)

  const engineCaseSensistive = HyperFormula.buildFromArray(
    [
      ['=SEARCH(".B", "fooBarBaz")'],
      ['=SEARCH(".B", "fooBarBaz", 5)'],
      ['=SEARCH(".b", "fooBarBaz")'],
      ['=SEARCH(".b", "fooBarBaz", 5)'],
    ],
    {useRegularExpressions: true, caseSensitive: true}
  )
  expect(engineCaseSensistive.getCellValue(adr('A1'))).toEqual(3) // getting ErrorMessage.PatternNotFound
  expect(engineCaseSensistive.getCellValue(adr('A2'))).toEqual(6) // getting 4
  expect(engineCaseSensistive.getCellValue(adr('A3'))).toEqualError(detailedError(ErrorType.VALUE, ErrorMessage.PatternNotFound)) // getting 3
  expect(engineCaseSensistive.getCellValue(adr('A4'))).toEqualError(detailedError(ErrorType.VALUE, ErrorMessage.PatternNotFound)) // getting 6
  })
```
Or in this JSFiddle example - [hyperformula-bug-search](https://jsfiddle.net/thilgen/nhat8d9w/35/)

### Related issues:
1. https://github.com/handsontable/hyperformula/issues/1224
2. https://github.com/handsontable/hyperformula/pull/1226

### Your environment
Mac + Chrome
Handsontable: v12.3.3 (28/03/2023 12:24:28)
HyperFormula: 2.3.0"

### Links
<!--- [optional] Any links that are related  -->

### Additional contract requirements

`SEARCH` is case-insensitive regardless of the engine's `caseSensitive` configuration option, for both wildcard and regular-expression patterns. In particular, with `useRegularExpressions: true` and `caseSensitive: true`:

- `=SEARCH(".b", "fooBarBaz")` returns `3`
- `=SEARCH(".b", "fooBarBaz", 5)` returns `6`

When the pattern is not found, `SEARCH` returns the `#VALUE!` error with the `Pattern not found.` message (`ErrorMessage.PatternNotFound`), including when a `Start_position` argument is supplied.
