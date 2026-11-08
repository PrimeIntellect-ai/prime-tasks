Invalid deprecation error for Date::startOfWeek()
I just updated my installation of Chronos to the latest available version for the project (PHP 7.3, so best I get is 2.4.4), and I got this nonsensical error:
`(new Date($anyDateHere))->addWeeks(1)->startOfWeek()`
throws
`2.5 startOfDay() will be removed in 3.x.`
[HIDDEN]

### Additional contract requirements

- Calling `Date::startOfWeek()` through the reported chain must not emit a `startOfDay()` deprecation.
