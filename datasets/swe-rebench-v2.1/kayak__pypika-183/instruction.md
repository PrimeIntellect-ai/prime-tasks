Interval query trims right zeros for integer values
--------------------------------------------------
[System environment]

OS     : CentOS 7.5 and Ubuntu 16.04 LTS
PyPika : 0.15.1

--------------------------------------------------
[Overview]

When numbers ending in zero (such as 10, 100, etc.) are specified in
Interval class (terms.py), all consective zeros are accidentally
trimmed.

https://github.com/kayak/pypika/blob/master/pypika/terms.py#L952

I guessed that a regular expression specified in 'self.trim_pattern'
might be inappropriate.

https://github.com/kayak/pypika/blob/master/pypika/terms.py#L910

--------------------------------------------------
[Steps to reproduce]

>>> from pypika import Interval
>>> Interval(seconds=100).get_sql()

--------------------------------------------------
[Expected behavior]

>>> Interval(seconds=100).get_sql()

"INTERVAL '100 SECOND'"

--------------------------------------------------
[Actual behavior]

>>> Interval(seconds=100).get_sql()

"INTERVAL '1 SECOND'"
