v5 regression: `next()` doesn't set milli-seconds correctly
v5 doesn't set the milli-seconds to zero for the next date. They are carried over from `currentDate` instead.

```ts
const cronExpression = CronExpressionParser.parse('* * * * *', {
   currentDate: '2020-03-06T10:02:01.002Z',
   tz: 'Europe/Berlin'
 })
 const res = cronExpression.next().toISOString()
```
`res` is "2020-03-06T10:03:00.002Z" in v5, but should be "2020-03-06T10:03:00.000Z". With v4 the milli-seconds were correct.
