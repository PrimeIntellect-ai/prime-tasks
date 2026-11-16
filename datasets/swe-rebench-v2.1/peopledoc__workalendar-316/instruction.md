Wrong UnitedKingdom holidays for 2012
workalendar==4.0.0 from PYPI
python 3.6 on LINUX

Hi, thanks for this library that is exactly what I'm looking for.
One issue I have is with holidays in the UK that seem to be wrong for years when the government "randomly" decided to add some. The last example is the Queen’s Diamond Jubilee.
Here is the official link: https://www.gov.uk/bank-holidays with 2012 at the end of the page.

The great thing about this year is:
- There is an additional bank holiday on June 5
- The usual Spring bank holiday is **not** the last Monday of May (May 28) but  June 4.

I don't have a complete list (yet) but there are other years with similar holiday like 2002.

Are these holiday something you see being in the scope of workalendar?
I'll probably fork your repo to manage them anyway so I'm interested to know if you are open to a PR to manage these cases. If it's the case there may be a way you prefer me to go to manage this.

Bellow the code I run with the missing and wrong date:

    from workalendar.europe import UnitedKingdom
    cal = UnitedKingdom()
    cal.holidays(2012)

Gives me:
    [(datetime.date(2012, 1, 1), 'New year'),
     (datetime.date(2012, 1, 2), 'New Year shift'),
     (datetime.date(2012, 4, 6), 'Good Friday'),
     (datetime.date(2012, 4, 8), 'Easter Sunday'),
     (datetime.date(2012, 4, 9), 'Easter Monday'),
     (datetime.date(2012, 5, 7), 'Early May Bank Holiday'),
     (datetime.date(2012, 5, 28), 'Spring Bank Holiday'),
     (datetime.date(2012, 8, 27), 'Late Summer Bank Holiday'),
     (datetime.date(2012, 12, 25), 'Christmas Day'),
     (datetime.date(2012, 12, 26), 'Boxing Day')]

Thanks.

### Additional contract requirements

For the 2002 United Kingdom and Northern Ireland holiday calendars, include the additional bank holiday on June 3 and observe the Spring Bank Holiday on June 4 instead of its usual late-May date of May 27. A separate holiday on May 27 may also appear in the calendar; the Spring Bank Holiday itself is observed on June 4.
