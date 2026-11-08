localedata.locale_identifiers is slow
# localedata.locale_identifiers is slow

`localedata.locale_identifiers` reads the available locale identifiers from disk every time it is called. Since the locale data files are distributed with the lib, there shouldn't be a need to scan the disk every time this is called, as it could be cached.

I noticed a hot spot in this method when profiling a service that uses this library. Specifically I noticed that babel.Locale.parse performs very poorly when supplied bogus locales. I ran a small benchmark to demonstrate this:

# Steps to Reproduce

```
import timeit

import babel


def wrapped():
    try:
        babel.Locale.parse("en_ZH")
    except babel.UnknownLocaleError:
        pass


print(timeit.timeit(wrapped, number=1000))
```

# Actual Results
Above snippet takes several seconds to execute.

Output on my machine:
```
3.91633701324
```

# Expected Results
Should be much faster.

# Reproducibility
100%

# Additional Information:
[HIDDEN]

### Additional contract requirements

- Repeated calls to `localedata.locale_identifiers` must avoid rescanning the packaged locale-data directory for identifiers.
