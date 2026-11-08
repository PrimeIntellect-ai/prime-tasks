includesDate doesn't properly account for special character expressions
I think the includesDate method may have a bug as it doesnt seems to support nth day expressions

```
const laborDayExpr = '* * * * SEP MON#1'
const interval = CronExpressionParser.parse(laborDayExpr, { strict: true })

const firstMonday = new Date('2025-09-01T23:00:00.000Z') // first monday in september
expect(interval.includesDate(firstMonday)).toBeTrue() ---> pass

const secondMonday = new Date('2025-09-08T23:00:00.000Z') // second monday in september
expect(interval.includesDate(secondMonday)).toBeFalse()  ----> fails since includesDate returns true
```

Similarly, for `L`

```
const memorialDayExpr = '* * * * MAY MONL'
const interval = CronExpressionParser.parse(memorialDayExpr, { strict: true })

const lastMonday = new Date('2025-05-05T23:00:00.000Z') // last monday in may
expect(interval.includesDate(lastMonday)).toBeTrue() ---> pass

const firstMonday = new Date('2025-05-26T23:00:00.000Z') // first monday in may
expect(interval.includesDate(firstMonday)).toBeFalse() ----> fails since includesDate returns true
```

This is because the parser doesn't seem to apply the special characters to the `values`, and the `includesDate` method checks the `values` for a match.

### Additional contract requirements

- For a weekday `L` expression, `includesDate` must match the final occurrence of that weekday in the month. For `MONL` in May 2025, May 26 matches and May 5 does not; the date labels and expected results in the supplied May example are reversed.
