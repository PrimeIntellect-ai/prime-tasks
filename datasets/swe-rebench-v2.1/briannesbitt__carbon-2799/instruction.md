diffInWeekdays returns unexpected values
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

I encountered an issue with the following code. I'd expect only the dates to matter here but it seems that just an hour (or a second, doesn't matter) of difference counts as a weekday and 25 hours counts as two weekdays.
<!--
    ⚠️ Your code below (not the code from inside Carbon library)
    Be sure it's dependency-free and enough to reproduce the issue
    when we run it on:
    https://play.phpsandbox.io/embed/nesbot/carbon
-->
```php
// 0 hour diff
$s1 = Carbon::create(2023, 6, 6, 15, 0, 0);
$e1 = Carbon::create(2023, 6, 6, 15, 0, 0);

echo $s1->diffInWeekdays($e1) . PHP_EOL;

// 1 hour diff
$s2 = Carbon::create(2023, 6, 6, 15, 0, 0);
$e2 = Carbon::create(2023, 6, 6, 16, 0, 0);

echo $s2->diffInWeekdays($e2) . PHP_EOL;

// 23 hour diff
$s3 = Carbon::create(2023, 6, 6, 15, 0, 0);
$e3 = Carbon::create(2023, 6, 7, 14, 0, 0);

echo $s3->diffInWeekdays($e3) . PHP_EOL;

// 24 hour diff
$s4 = Carbon::create(2023, 6, 6, 15, 0, 0);
$e4 = Carbon::create(2023, 6, 7, 15, 0, 0);

echo $s4->diffInWeekdays($e4) . PHP_EOL;

// 25 hour diff
$s5 = Carbon::create(2023, 6, 6, 15, 0, 0);
$e5 = Carbon::create(2023, 6, 7, 16, 0, 0);

echo $s5->diffInWeekdays($e5) . PHP_EOL;
```

Carbon version: **2.67.0**
<!--
    ⚠️ Run the command `composer show nesbot/carbon` to get "versions"
-->

PHP version: **7.4.10**

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
0
0
1
1
1
```
<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

But I actually get:

```
0
1
1
1
2
```
<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!
