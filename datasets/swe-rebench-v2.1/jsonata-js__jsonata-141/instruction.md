ISO 8601 check for toMillis is too strict
The ISO 8601 date check for the `toMillis()` function is too strict and only accepts dates in the format `2018-01-31T17:39:00.000Z` or `2018-01-31T17:39:00.000+00:00` rather than the wider range of valid dates which is possible such as `2018-01-31` or `2018-01-31T17:39:00.000+0000` (the latter of which is where I stumbled upon this issue).
