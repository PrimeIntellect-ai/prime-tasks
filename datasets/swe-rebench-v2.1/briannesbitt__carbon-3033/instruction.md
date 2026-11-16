Check month issue
<!--
    🛑 Important notice to read.

    Before anything else, please search in previous issues (both open and close):
    https://github.com/briannesbitt/Carbon/issues?q=is%3Aissue

    ⚠️ Please don't create an issue about a problem already disccussed or addressed.

    ⚠️ Please check if the documentation (https://carbon.nesbot.com/docs/) answer
    your question or talk about the behavior you're about to describe.

    Note that Carbon extends the PHP DateTime class
    (https://www.php.net/manual/en/class.datetime.php) be sure you report
    a Carbon-specific problem, if the same happens using DateTime,
    refer to https://github.com/php/php-src

    ⚠️ Don't remove this template.
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
Hello,

I encountered an issue with the following code:
<!--
    ⚠️ Your code below (not the code from inside Carbon library)
    Be sure it's dependency-free and enough to reproduce the issue
    when we run it on:
    https://play.phpsandbox.io/embed/nesbot/carbon
-->
```php
        $reportDate = now()->subMonth()->lastOfMonth();
        dd($reportDate->is('May'), $reportDate->is('April'));
```

Carbon version: *** 2.67.0**
<!--
    ⚠️ Run the command `composer show nesbot/carbon` to get "versions"
-->

PHP version: **8.1.2**

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
true, false
```
<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

But I actually get:

```
true, true
```
<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Thanks!
