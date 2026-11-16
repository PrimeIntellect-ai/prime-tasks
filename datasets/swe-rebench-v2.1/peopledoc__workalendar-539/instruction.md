BUG: duplicate shifted holiday in California
``` python
from workalendar.usa import California

cal = California()

cal.holidays(2019)
Out[13]:
[(datetime.date(2019, 1, 1), 'New year'),
 (datetime.date(2019, 1, 21), 'Birthday of Martin Luther King, Jr.'),
 (datetime.date(2019, 2, 18), "Washington's Birthday"),
 (datetime.date(2019, 3, 31), 'Cesar Chavez Day'),
 (datetime.date(2019, 4, 1), 'Cesar Chavez Day (Observed)'),  # <===============
 (datetime.date(2019, 4, 1), 'Cesar Chavez Day (Observed)'),  # <===============
 (datetime.date(2019, 5, 27), 'Memorial Day'),
 (datetime.date(2019, 7, 4), 'Independence Day'),
 (datetime.date(2019, 9, 2), 'Labor Day'),
 (datetime.date(2019, 11, 11), 'Veterans Day'),
 (datetime.date(2019, 11, 28), 'Thanksgiving Day'),
 (datetime.date(2019, 11, 29), 'Thanksgiving Friday'),
 (datetime.date(2019, 12, 25), 'Christmas Day')]
```

**Note that Cesar Chavez Day (Observed) is duplicated.**

This does not occur for 2017, 2018, 2020, and 2021. I've just tested those five years. The same issue occurs with 2019 in the CaliforniaEducation calendar.

I noticed this issue because it breaks a version of my test for PR #527.
