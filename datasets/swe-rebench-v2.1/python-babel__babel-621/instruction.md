Weeknumber wrong for 2018-12-31
As mentioned in the docs babel.dates.format_date uses the ISO-Calendar when passing "YYYY" as format string.

Evaluating gives
```
babel.dates.format_date(datetime.datetime(2018,12,31
                                         ), format="w YYYY", locale='en_US')
>> u'53 2018'
```
The correct result should be 1 2019 by iso definitions.

Thanks for your reply

### Additional contract requirements

`format_date` with the `YYYY` pattern uses the ISO week-year (the year that
contains the ISO week of the date); for 2018-12-31 this is `2019` in every
locale.

The `w` pattern follows the requested locale's week-numbering rules. On
2018-12-31, formatting `w` alone produces week 1 for `de_DE` and week 53 for
`en_US`. For a combined `w YYYY` format, the locale-specific week number is
retained, while `YYYY` remains the ISO week-year: the result is `"1 2019"`
for `de_DE` and `"53 2019"` for `en_US`. This locale-specific combined result
clarifies and supersedes the upstream paragraph's `en_US` numerical
expectation.
