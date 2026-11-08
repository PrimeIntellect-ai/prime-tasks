WKTWriter toLineString methods do not output full precision
A recent commit to WKTWriter breaks the toLineString method output, because the use of Java formatting only outputs a limit number of decimals of precision.

This should be fixed by either reverting to the original code or using a different format.

It would be helpful to factor the coordinate string conversion into a common method.

Would also be good to have some unit tests covering this code.
