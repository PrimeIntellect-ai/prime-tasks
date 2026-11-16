Carbon ->toPeriod with interval / duration string fails after 3.2.1 version
<!--
    🛑 DON'T REMOVE ME.
    This issue template applies to all
      - bug reports,
      - feature proposals,
      - and documentation requests

    Having all those information will allow us to know exactly
    what you expect and answer you faster and precisely (answer
    that matches your Carbon version, PHP version and usage).

    Note: Comments between <!- - and - -> won't appear in the final
    issue (See [Preview] tab).
-->
Hello, after upgrading from [3.1.1](https://github.com/briannesbitt/Carbon/releases/tag/3.1.1) to [3.2.1](https://github.com/briannesbitt/Carbon/releases/tag/3.2.1) `->toPediod(..` throws an error.

I encountered an issue with the following code:
<!--
    ⚠️ Your code below (not the code from inside Carbon library)
    Be sure it's dependency-free and enough to reproduce the issue
    when we run it on:
    https://play.phpsandbox.io/embed/nesbot/carbon
-->
```php
$date1 = \Carbon\Carbon::parse('2018-06-01');
$date2 = \Carbon\Carbon::parse('2018-06-10');
$period = $date1->toPeriod($date2, 'P1D');
// before 3.2.1 -> works
// after 3.2.1 --> this error:

DatePeriod::__construct() accepts (DateTimeInterface, DateInterval, int [, int]), or (DateTimeInterface, DateInterval, DateTime [, int]), or (string [, int]) as arguments

  at vendor/nesbot/carbon/src/Carbon/CarbonPeriod.php:702
    698▕
    699▕         $raw ??= ['R1/2000-01-01T00:00:00Z/P1D'];
    700▕
    701▕         // Dummy construct, as properties are completely overridden
  ➜ 702▕         parent::__construct(...$raw);
    703▕
    704▕         if (isset($sortedArguments['start'])) {
    705▕             $this->setStartDate($sortedArguments['start']);
    706▕         }

```

Carbon version: **3.2.1**
<!--
    ⚠️ Run the command `composer show nesbot/carbon` to get "versions"
-->

PHP version: **8.3.4**

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
    then paste it in the issue. Then we can immediately get
    your issue.
-->


I expected to get:

```
a new \Carbon\CarbonPeriod instance.
```
<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

But I actually get:

```
DatePeriod::__construct() arguments error.
```
<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!
