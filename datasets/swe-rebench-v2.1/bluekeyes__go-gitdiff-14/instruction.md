'ParsePatchDate' is broken :/
`time.Parse` isn't guaranteed to throw errors, when it sees elements that it doesn't recognize it zeros them. https://play.golang.org/p/4kbScfG56Ic

> Elements omitted from the value are assumed to be zero or, when zero is impossible, one, so parsing "3:04pm" returns the time corresponding to Jan 1, year 0, 15:04:00 UTC (note that because the year is 0, this time is before the zero Time). Years must be in the range 0000..9999. The day of the week is checked for syntax but it is otherwise ignored.
- https://golang.org/pkg/time/#example_Parse

It might be worth checking the time to see if the year is 1 in addition to checking if err is nil, seeing that git was released in 2005 :D I know this would make it unusable for time travelers but :shrug:

Personally I would just use something like https://github.com/kierdavis/dateparser  https://play.golang.org/p/-yRXt4qPAZo

### Additional contract requirements

- `ParsePatchDate` must correctly parse a single-digit day of the month in its existing default, default-local, and RFC textual formats.
- A date is parsed only when the entire input matches a supported patch-date format. A time-only value such as `3:04pm` must remain unparsed while retaining its raw input.
