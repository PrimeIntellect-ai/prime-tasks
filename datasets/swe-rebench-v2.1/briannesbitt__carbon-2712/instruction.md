Locale is now ignored on weekday()
<!--
    🛑 DON'T REMOVE ME.
    This issue template apply to all
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

Since upgrading to the latest version of Carbon (2.63.0), I noticed that a few tests we're failing, because the weekday method was returning a different value. By looking at this [pull request](https://github.com/briannesbitt/Carbon/pull/2687/files), it looks like the method is now ignoring the set locale when no value parameter is given.

Code example that since the 2.63.2 update gives a different value in e.g. locale 'nl':
```php
echo Carbon::parse('2022-04-18')->weekday();
```
I expect to get the value `0` with locale 'nl', since in my locale the week starts on a monday.

However, since the locale is now ignored, I receive the value `1`, as it assumes that the week starts on Sunday.


Is this supposed to be the expected behavior and if so, how do I get the weekday in a given locale?

Carbon version: 2.63.0

PHP version: 8.1.12

<!--
    Run the command `composer show nesbot/carbon`
    to get "versions"
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


<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!

### Additional contract requirements

The locale-aware day-of-week value requested above is provided by
`getDaysFromStartOfWeek()`, which derives the first day of the week from the
instance locale unless an explicit week start is supplied. For the example
above (`2022-04-18` with locale `nl`), `getDaysFromStartOfWeek()` returns `0`.
`setDaysFromStartOfWeek()` sets the calendar date to the requested zero-based
day offset from the beginning of the week, using the instance locale unless an
explicit week start is supplied. Its first argument is the requested day
offset; its optional second argument is the explicit week start. The
`weekday()` getter itself returns the raw day-of-week index (0 = Sunday … 6 =
Saturday), regardless of locale.
