Duration.toISOTime has locale-dependent output (using ar-QA locale)
**Describe the bug**
We ran into a production error today trying to parse an ISO time passed from the client to the server. The client had an Arabic locale and for some reason the locale-formatted time value was making its way to the server and crashing the ISO parse.

**To Reproduce**
I eventually boiled down the problem to this repro (running in the console at https://moment.github.io/luxon) :
```javascript
> luxon.Settings.defaultLocale = "ar-QA"
'ar-QA'
> luxon.Duration.fromObject({hours: 1, minutes: 4}).toISOTime()
'٠١:٠٤:٠٠.٠٠٠'
> luxon.DateTime.now().toISOTime()
'16:53:34.372-04:00'
> luxon.Duration.fromISOTime(luxon.Duration.fromObject({hours: 1, minutes: 1}).toISOTime()).invalidExplanation
`the input "٠١:٠١:٠٠.٠٠٠" can't be parsed as ISO 8601`
```

**Actual vs Expected behavior**
`luxon.Duration.fromObject({hours: 1, minutes: 4}).toISOTime()` outputs `٠١:٠٤:٠٠.٠٠٠` in certain locales.
I would have expected the toISOTime to be locale-independent and always output `01:04:00.000`

If I'm misunderstanding the ISO standard in this case, I would at least expect the roundtrip not to fail:
```javascript
> luxon.Duration.fromISOTime(luxon.Duration.fromObject({hours: 1, minutes: 1}).toISOTime()).invalidExplanation
`the input "٠١:٠١:٠٠.٠٠٠" can't be parsed as ISO 8601`
```

**Desktop:**

- OS: Windows, Mac
- Browser: Chrome 111
- Luxon version: 3.3.0
- Your timezone: "America/New_York"

### Additional contract requirements

A time string produced by `Duration.toISOTime()` must be accepted by `Duration.fromISOTime()` and represent the same duration.
