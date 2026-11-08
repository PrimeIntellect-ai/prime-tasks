ValueError exception when asking for authored_datetime
I am receiving a `ValueError` exception when getting the author date of a commit in Rails project. You can replicate it with the following code:

```
> from git import Repo
> repo = Repo('rails')
> commit = repo.commit('4cf94979c9f4d6683c9338d694d5eb3106a4e734')
> commit.authored_datetime
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/dspadini/Documents/pydriller/.venv/lib/python3.6/site-packages/git/objects/commit.py", line 151, in authored_datetime
    return from_timestamp(self.authored_date, self.author_tz_offset)
  File "/Users/dspadini/Documents/pydriller/.venv/lib/python3.6/site-packages/git/objects/util.py", line 124, in from_timestamp
    > local_dt = utc_dt.astimezone(tzoffset(tz_offset))
ValueError: offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24).
```

Tracing back the error, I got that the timestamp of the commit is 1312735823, while the tz_offset is -1864800. The problem is when creating the tzoffset: I indeed printed the timedelta
```
local_dt = utc_dt.astimezone(tzoffset(tz_offset))

class tzoffset(tzinfo):
    def __init__(self, secs_west_of_utc, name=None):
        self._offset = timedelta(seconds=-secs_west_of_utc)
        print('Timedelta is {}'.format(timedelta(seconds=-secs_west_of_utc)))
```
and it is not in the range of [-24,24] hours, but it is actually 21 days.

*EDIT*: looking at the information of the commit, the offset is completely wrong:
`Date:   Mon Aug 29 06:50:23 2011 +51800`

So the problem is not of gitpython.

### Additional contract requirements

- If a timezone offset is outside the valid range and cannot be represented, conversion must still return a `datetime` rather than raise `ValueError`. The returned datetime should represent the timestamp in UTC.
