Add support for ISO 8601 basic format to DateTime.toISO()
From [Wikipedia](https://en.wikipedia.org/wiki/ISO_8601):

> Representations can be done in one of two formats – a basic format with a minimal number of separators or an extended format with separators added to enhance human readability. The standard notes that "The basic format should be avoided in plain text." The separator used between date values (year, month, week, and day) is the hyphen, while the colon is used as the separator between time values (hours, minutes, and seconds). For example, the 6th day of the 1st month of the year 2009 may be written as "2009-01-06" in the extended format or simply as "20090106" in the basic format without ambiguity.

This could be done as a `{ format: 'basic' }` option with the default being `{ format: 'extended' }`. This format is useful when used in a URL.

### Additional contract requirements

- `DateTime.toISO(opts)` accepts an optional options object. `opts.format` is `"basic"` or `"extended"` and defaults to `"extended"`. In the basic format the date is `yyyyMMdd`, the time is `HHmmss.SSS`, and the offset is `Z` for UTC or `±hhmm` otherwise, joined by `T` (for example `19820525T092354.123Z`).
- `DateTime.toISODate(opts)` accepts `opts.format` (`"basic"` or `"extended"`, default `"extended"`). The extended format is `yyyy-MM-dd`; the basic format is `yyyyMMdd`. It returns `null` for invalid DateTimes.
- `DateTime.toISOTime(opts)` accepts `opts.format` (`"basic"` or `"extended"`, default `"extended"`), `opts.suppressMilliseconds`, `opts.suppressSeconds`, and `opts.includeOffset`. The extended format is `HH:mm:ss.SSS`; the basic format is `HHmmss.SSS`. The offset is `Z` for UTC, `±hh:mm` in the extended format, and `±hhmm` in the basic format. It returns `null` for invalid DateTimes.
