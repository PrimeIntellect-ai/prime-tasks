Large Unix times are not retrieved correctly
My application stores dates as Unix times, integers that represent the number of seconds since January 1st, 1970. This works well in most cases but I noticed a spurious date -- August 30th, 1754 -- occasionally being returned in my Go queries. After some investigation I was able to trace this behaviour to go-sqlite3's handling of Unix times.

When writing to the database, I convert Time values to Unix times with the time.Unix() method. When reading from the database, go-sqlite3 handles the conversion from Unix time back to Time. However this can fail (silently) with large Unix times. For example, if you write a zero Time value to the database as an integer and then query it, you get the aforementioned date August 30th, 1754, even though the Unix time in the database is correct.

Calling time.Time{}.Unix() returns a large negative integer. [HIDDEN] See this [code snippet](https://play.golang.org/p/-RVHH-W-LB) for an illustration.

Any sufficiently large Unix time will overflow when multiplied by a billion. According to my tests, go-sqlite3 will hit problems with dates pre-1677 or post-2262. These are edge cases for sure but the fix is trivial. I can submit a PR if there's any interest.

### Additional contract requirements

Integer timestamps expressed as Unix seconds must be retrieved as the corresponding Go time even for sufficiently large positive values beyond the year 2262, without overflow.
