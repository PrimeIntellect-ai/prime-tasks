Inconsistent duration calculations around some dates
**Describe the bug**

Luxon seems to get wrong results for some date diff operations.

**To Reproduce**

Try the code below (you can find it at https://runkit.com/bogdanb/luxon-year-100):

```
const z = luxon.DateTime.fromISO('0099-12-31', {zone: "utc"})
const a = luxon.DateTime.fromISO('0100-03-01', {zone: "utc"})
const b = luxon.DateTime.fromISO('0100-03-02', {zone: "utc"})

console.log("diffs:",  a.diff(z), b.diff(z))
console.log("diffs as days:", a.diff(z).as('days'), b.diff(z).as('days'))
console.log("day diffs:", a.diff(z, 'days'), b.diff(z, 'days'))
console.log("day diffs as days:", a.diff(z, 'days').as('days'), b.diff(z, 'days').as('days'))
```

**Actual vs Expected behavior**

I would expect the two methods to get the same results, and, for each method, the two diffs to be separated by one day. In practice, the first calculation method returns 60 & 61 days, while the second returns 60 and 62 days. (Unless I’m missing something, the first one should be the correct one.)

Note that if you use `0100-01-01` (or a later date) for `z`, then the two calculation methods agree.

**Desktop (please complete the following information):**

- OS: Windows (but I doubt it matters).
- Browser: Chrome & Firefox, plus I think RunKit runs directly in node.
- Luxon version: 3.2.1
- Timezone: UTC

**Additional context**

Note that year 100 is not a leap year, because even if it’s divisible by 4, it’s divisible by 100 but not by 400. I’m not sure this is the problem, I tried other years like that and I could not reproduce the issue.
