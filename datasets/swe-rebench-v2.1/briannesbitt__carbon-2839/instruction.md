Carbon period does not accept intervals smaller than 1
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
$period = \Carbon\CarbonPeriod::since('2018-04-21 00:00:00')->hours(0.5)->until('2018-04-21 02:00:00');
$timestamps = [];
foreach ($period->toArray() as $date) {
    $timestamps[]= $date->format('Y-m-d H:i:s');
}
var_export($timestamps);
```

Carbon version: **2.66.0**
<!--
    ⚠️ Run the command `composer show nesbot/carbon` to get "versions"
-->

PHP version: **8.2.4**

<!--
    Use `echo phpversion();`
    to get PHP version.

    Some issues can depends on your context, settings,
    macros, timezone, language. So to be sure the code
    you give is enough to reproduce your bug, try it
    first in:
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')-%3EsubDay()-%3Emonth%3B

    You can use the [Options] button to change the version
    then when you get the bug with this editor, you can use
    the [Export] button, copy the link of the opened tab,
    then paste it in the issue. Then we can immediatly get
    your issue.
-->


I expected to get:

```
array (
  0    '2018-04-21 00:00:00',
  1    '2018-04-21 00:30:00',
  2    '2018-04-21 01:00:00',
  3    '2018-04-21 01:30:00',
  4    '2018-04-21 02:00:00',
)
```
<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

But I actually get:

```
Carbon\Exceptions\InvalidIntervalException with message 'Empty interval is not accepted.'
```
<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!

### Additional contract requirements

- `CarbonInterval::enableFloatSetters(bool $floatSettersEnabled = true): void` is a public static method that globally enables float setters, and disables them again when passed `false`.
- While float setters are enabled, `CarbonInterval::hours()` accepts a fractional value and keeps its fractional part, so `hours(0.5)` yields 30 minutes.
- While float setters are disabled, a fractional value passed to `CarbonInterval::hours()` is truncated to an integer, as before.
- `CarbonPeriod::hours()` accepts a fractional step only while float setters are enabled. The timestamps shown in the reproduction are obtained when `CarbonInterval::enableFloatSetters()` has been called before constructing the period; when float setters are disabled, the fractional step is rejected.
- When setting a fractional hour would override a non-zero minute value, a `RuntimeException` is thrown with the message `You cannot set hour to a float value as minute would be overridden, set it first to 0 explicitly if you really want to erase its value`.
