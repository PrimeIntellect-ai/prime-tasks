[BUG] Events not equal although times are equal (only timezones differ, not actual time)
<!-- This template is there to guide you and help us. If you can not complete everything here, that is fine. -->
## Describe the bug
<!-- A clear and concise description of what the bug is. -->

If event times are equal but their timezones differ, then the events are not equal although they happen to have the same info in it.

## To Reproduce
<!-- Please add the necessary code here to reproduce the problem on your machine. -->

```
>>> from icalendar import Event
>>> from zoneinfo import ZoneInfo
>>> e1 = Event()
>>> e2 = Event()
>>> from datetime import datetime
>>> d1 = datetime(2025, 5, 8, 12, 0, tzinfo=ZoneInfo("UTC"))
>>> d2 = d1.astimezone(ZoneInfo("Europe/Zurich"))
>>> d2 == d1
True
>>> e1 == e2
True
>>> e1.start = d1
>>> e2.start = d2
>>> e1 == e2
False
```

## Expected behavior
<!-- A clear and concise description of what you expected to happen. -->

```
>>> e1 == e2
True
```

## Environment
<!-- please complete the following information: -->
 - [x] OS: Ubuntu                              <!-- e.g. Ubuntu 22 or Windows 10 -->
 - [x] Python version:  3.9          <!-- e.g. Python 3.10 -->
 - [x] `icalendar` version: 6.2.0     <!-- python3 -c 'import icalendar; print(icalendar.__version__)' -->

## Additional context
<!-- Add any other context about the problem here, related issues and pull requests. -->
- [x] I tested it with the latest version `pip3 install https://github.com/collective/icalendar.git`
- [x] I attached the ICS source file or there is no ICS source file
