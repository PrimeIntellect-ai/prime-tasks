Exceptions with date ranges
Hey,

as far as I see the related code it is not possible, right now, that I can define a date range as exception.

Like
```
'exceptions' => [
                    '2016-11-11-2016-11-25' => ['09:00-12:00'],
```
or am I wrong?

That would be a possible feature request.

### Additional contract requirements

- A date range in the `exceptions` configuration is written as two endpoints separated by either `-` or `to` (surrounding whitespace is ignored). Each endpoint may be a full date (`YYYY-MM-DD`) or a month-day (`MM-DD`). Every date in the range (inclusive) receives the configured hours.


- When a full-date exception and a recurring month-day exception both apply to a date, the full-date exception takes precedence.
