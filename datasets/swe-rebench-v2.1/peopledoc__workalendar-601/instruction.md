New agreed public holiday in Russia
Dear workalendar team,

We were notified, that recently, the Russian government agreed on the occupational calendar for 2021, which brings additional logic to some of the holidays.

### Year 2021
Is it possible to adjust the holidays for Russia since 2021 accordingly?

The current result:
```python
from workalendar.europe import Russia
Russia().holidays(2021)
[(datetime.date(2021, 1, 1), 'New year'),
 (datetime.date(2021, 1, 2), 'Day After New Year'),
 (datetime.date(2021, 1, 7), 'Christmas'),
 (datetime.date(2021, 2, 23), 'Defendence of the Fatherland'),
 (datetime.date(2021, 3, 8), "International Women's Day"),
 (datetime.date(2021, 5, 1), 'Labour Day'),
 (datetime.date(2021, 5, 9), 'Victory Day'),
 (datetime.date(2021, 6, 12), 'National Day'),
 (datetime.date(2021, 11, 4), 'Day of Unity')]
```

The expected result:
_Note: Saturday 2020-02-20 becomes a working day_
```python
from workalendar.europe import Russia
Russia().holidays(2021)
[(datetime.date(2021, 1, 1, "New Year"),
(datetime.date(2021, 1, 2, "Day After New Year"),
(datetime.date(2021, 1, 3, "Another Day After New Year"),
(datetime.date(2021, 1, 4, "Third Day after New Year"),
(datetime.date(2021, 1, 5, "Fourth Day after New Year"),
(datetime.date(2021, 1, 6, "Fifth Day after New Year"),
(datetime.date(2021, 1, 7, "Christmas"),
(datetime.date(2021, 1, 8, "Day After Christmas"),
#(datetime.date(2021, 2,20, "working day, Saturday"),
(datetime.date(2021, 2, 22, "Day Before Defendence of the Fatherland"),
(datetime.date(2021, 2, 23, "Defendence of the Fatherland"),
(datetime.date(2021, 3, 8, "International Women's Day"),
(datetime.date(2021, 5, 1, "International Workers' Day"),
(datetime.date(2021, 5, 3, "Compensation holiday because International Workers' Day was Saturday"),
(datetime.date(2021, 5, 9, "Victory Day"),
(datetime.date(2021, 5, 10, "Compensation holiday because Victory Day was Sunday"),
(datetime.date(2021, 6, 12, "National Day"),
(datetime.date(2021, 6, 14, "Compensation holiday because National Day was Saturday"),
(datetime.date(2021, 11, 4, "Day of Unity"),
(datetime.date(2021, 11, 5, "Day After Day of Unity"), #just because it is a bridge Friday
(datetime.date(2021, 12, 31, "31st December")]
```

### Past years
Could you also fix the past years (e.g. the year [2020](https://www.timeanddate.com/calendar/custom.html?year=2020&country=20&cols=3&hol=1&df=1) having some missing holidays)? Even though this is past information, it is relevant for the machine learning models during the fitting time.

### Related sources
http://www.consultant.ru/law/ref/calendar/proizvodstvennye/2021/
https://www.timeanddate.com/calendar/custom.html?year=2021&country=20&cols=3&hol=1&df=1

### Additional contract requirements

Past-year corrections are limited to the 2020 calendar described in this section. For 2020, Russia's holiday calendar must include January 7 as Christmas. Preserve the February 23 holiday and February 24 compensatory holiday, the March 8 holiday and March 9 compensatory holiday, the May 9 holiday and May 11 compensatory holiday, and all non-working days from March 28 through April 30 inclusive. Also include May 4, May 5, May 6, May 7, May 8, and the July 1 public holiday.

For 2021, retain the holiday dates and shifted dates in the expected schedule. The May 1 holiday is International Workers' Day; the holidays shifted to May 3, May 10, and June 14 must be identified as compensatory holidays for the corresponding weekend holidays. February 20, 2021 is a working day.
