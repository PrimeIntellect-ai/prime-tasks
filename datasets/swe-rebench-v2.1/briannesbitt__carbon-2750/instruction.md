isLongYear() is not determined from the ISO 8601 year
<!--
    🛑 DON'T REMOVE ME.
    This issue template applies to all
      - bug reports,
      - feature proposals,
      - and documentation requests

    Having all those informations will allow us to know exactly
    what you expect and answer you faster and precisely (answer
    that matches your Carbon version, PHP version and usage).

    Note: Comments between <!- - and - -> won't appear in the final
    issue (See [Preview] tab).
-->
Hello,

I encountered an issue with the following code:
<!--
    ⚠️ Your code below (not the code from inside Carbon library)
    Be sure it's dependency-free and enough to reproduce the issue
    when we run it on:
    https://play.phpsandbox.io/embed/nesbot/carbon
-->
```php
$date_1 = Carbon::parse('December 30, 2019');
$date_2 = Carbon::parse('January 1, 2020');

echo $date_1->isoFormat('G-W-E') . PHP_EOL;
echo $date_2->isoFormat('G-W-E') . PHP_EOL;

echo $date_1->isLongYear() ? 'true' : 'false' . PHP_EOL; // false, should be true if this based on the ISO year
echo $date_2->isLongYear() ? 'true' : 'false' . PHP_EOL; // true
```

Carbon version: 2.62.1
PHP version: 8.1.7

I expected to get true for both as the above dates are in ISO week 1 of 2020.  But `Carbon::parse('December 30, 2019')->isLongYear() ` is `false` while `Carbon::parse('January 1, 2020')->isLongYear()` is `true`.

<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!

### Additional contract requirements

The fix for this issue is the new public method `isLongIsoYear()`. The existing
`isLongYear()` method is intentionally left unchanged: it determines long-year status from
the calendar year (the numeric year), ignoring the month and day. The ISO-8601 week-year
based determination described in the report is provided by `isLongIsoYear()`.

`isLongYear()` returns `true` exactly when the calendar year of the instance is a long year
(contains 53 ISO weeks). Exact expected values:

- `Carbon::createFromDate(2015, 1, 1)->isLongYear()` is `true`
- `Carbon::createFromDate(2020, 1, 1)->isLongYear()` is `true`
- `Carbon::createFromDate(2016, 1, 1)->isLongYear()` is `false`
- `Carbon::createFromDate(2019, 12, 29)->isLongYear()` is `false`

`isLongIsoYear()` returns `true` exactly when the ISO-8601 week-year of the instance is a
long year (contains 53 ISO weeks). The ISO week-year is determined from the instance's local
date, i.e. using the instance's timezone. Exact expected values:

- `Carbon::createFromDate(2015, 1, 1)->isLongIsoYear()` is `true`
- `Carbon::createFromDate(2016, 1, 1)->isLongIsoYear()` is `true`
- `Carbon::createFromDate(2019, 12, 30)->isLongIsoYear()` is `true`
- `Carbon::createFromDate(2016, 1, 3)->isLongIsoYear()` is `true`
- `Carbon::createFromDate(2019, 12, 29)->isLongIsoYear()` is `false`
- `Carbon::createFromDate(2018, 12, 31)->isLongIsoYear()` is `false`

Because the ISO week-year follows the instance's local date, the same instant can belong to a
long ISO year in one timezone and not in another. For example,
`Carbon::parse('2019-12-30 00:30:00', 'UTC')->isLongIsoYear()` is `true`, while the same
instant viewed in the `Etc/GMT+12` timezone (local date `2019-12-29`) is `false`.
