tzOffset does not work with decimal values
Hi, I am trying to get the cron time to come out in Indian Standard Time (GMT + 5.30) and I have tried this but the output I get is incorrect.

```js
var cronstrue = require("cronstrue")
cronstrue.toString("31 10 * * *", {
    tzOffset: 5.5
})
```

Expected: `At 4:01 PM`
Got: `At .5:31 PM`

Is there something I am missing?
