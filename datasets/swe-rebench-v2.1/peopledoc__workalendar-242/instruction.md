2017 UnitedStates Christmas Day calculation is wrong
```
(datetime.date(2017, 12, 24), 'Christmas Eve'),
(datetime.date(2017, 12, 25), 'Christmas Day'),
(datetime.date(2017, 12, 25), 'Christmas Eve (Observed)'),
(datetime.date(2017, 12, 26), 'Christmas Eve (Observed)'),
(datetime.date(2017, 12, 27), 'Christmas Day (Observed)')
```

It should be:

```
(datetime.date(2017, 12, 24), 'Christmas Eve'),
(datetime.date(2017, 12, 25), 'Christmas Day'),
(datetime.date(2017, 12, 25), 'Christmas Eve (Observed)'),
(datetime.date(2017, 12, 26), 'Christmas Day (Observed)')
```

### Additional contract requirements

The corrected Christmas shift applies to any calendar that includes Christmas
Eve (for example, `workalendar.usa.Arkansas`). For such a calendar in 2017,
Christmas Day (Observed) is on 2017-12-26 and 2017-12-27 is not a holiday.
