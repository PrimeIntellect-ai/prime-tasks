Invalid unit when giving quarters to diff method
Hello,
I found an issue when passing `quarters` unit to the `diff` method:

```
luxon.DateTime.local().diff(luxon.DateTime.fromMillis(0), 'quarters')

duration.js:324 Uncaught Error: Invalid unit undefined
    at normalizeUnit (duration.js:324)
    at normalizeObject (util.js:259)
    at Function.fromObject (duration.js:245)
    at _diff (diff.js:70)
    at DateTime.diff (datetime.js:1760)
    at <anonymous>:1:24
```
