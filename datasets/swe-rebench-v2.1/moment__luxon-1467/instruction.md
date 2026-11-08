`Duration#normalize` has trouble with negative milliseconds
**Describe the bug**
Fails to normalize a Duration with negative milliseconds.

**To Reproduce**
I was able to repro this in the playground in the docs:
```javascript
> luxon.VERSION
'2.4.0'

> let d = luxon.Duration.fromObject({seconds: -44, milliseconds: -100, minutes: 1})

> d.normalize()
Duration {values: {…}, loc: Locale, conversionAccuracy: 'casual', invalid: null, matrix: {…}, …}
...
values: {seconds: 16, milliseconds: -100, minutes: 0}
```

I would expect the above to be {seconds: 15, milliseconds: 900, minutes: 0}

Out of curiosity, I tried the initializing the "right" duration, and it has no issues normalizing:

```javascript
> let m = luxon.Duration.fromObject({seconds: 15, milliseconds: 900})

> m.normalize()
Duration {values: {…}, loc: Locale, conversionAccuracy: 'casual', invalid: null, matrix: {…}, …}
...
values: {seconds: 15, milliseconds: 900}
```


**Actual vs Expected behavior**
Since the overall duration is greater than zero, I expect all normalized fields to be greater than zero.

**Desktop (please complete the following information):**

- OS: MacOS 11.6.5
- Browser: Chrome Version 102.0.5005.115 (Official Build) (x86_64)
- Luxon version: 2.4.0 (used your playground)
- Your timezone "America/New_York"

**Additional context**
This library is excellent, by the way!

### Additional contract requirements

- For a duration whose total is positive, `normalize()` should produce nonnegative fields; zero-valued fields are permitted.
