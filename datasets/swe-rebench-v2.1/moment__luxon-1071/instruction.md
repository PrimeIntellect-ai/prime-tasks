Parsing fractional hours durations
**Describe the bug**
I've discovered this problem when trying to parse back ISO duration acquired from Luxon previously. Many of my durations ended up being empty objects. After some further investigation, it appears to be a problem in parsing fractional hours durations.


**To Reproduce**

I've made following test case to prove this problem: 478abdc82319336b5ab1b6b385927e5bde423eb4

You can also test this problem in my RunKit: https://runkit.com/spodjasek/luxon-fractional-hours

**Actual vs Expected behavior**

After running:
```javascript
Duration.fromISO('PT9.5H').toObject()
```

I expect returned object to be:
```javascript
{hours: 9.5}
```

Instead of above I receive empty object:
```
{}
```

**Desktop (please complete the following information):**

- OS: Linux
- Run on Node
- Luxon version 2.0.2
- Timezone `Europe/Warsaw`, but also tested in `America/New_York`
