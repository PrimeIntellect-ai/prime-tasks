Can no longer use `createFromFormat` with an non-string value as time input
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
Hello,

I encountered an issue with the following code after upgrading to Carbon v3 as part of the Laravel 11 upgrade:
<!--
    ⚠️ Your code below (not the code from inside Carbon library)
    Be sure it's dependency-free and enough to reproduce the issue
    when we run it on:
    https://play.phpsandbox.io/embed/nesbot/carbon
-->
```php
CarbonImmutable::createFromFormat('U', 1709589519);
```

Carbon version: 3.1.1
<!--
    ⚠️ Run the command `composer show nesbot/carbon` to get "versions"
-->

PHP version: 8.3

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

A CarbonImmutable object is successfully created.

<!--
    Always give your expectations. Each use has their owns.
    You may want daylight saving time to be taken into account,
    someone else want it to be ignored. You may want timezone
    to be used in comparisons, someone else may not, etc.
-->

But I actually get:

An exception thrown with the following message:

```
Carbon\CarbonImmutable::rawCreateFromFormat(): Argument #2 ($time) must be of type string, int given, called in /home/vagrant/atlas/vendor/nesbot/carbon/src/Carbon/Traits/Creator.php on line 647

```
<!--
    If you did not succeed to get the same result in
    https://play.phpsandbox.io/embed/nesbot/carbon?input=%3C%3Fphp%0A%0Aecho%20Carbon%3A%3Aparse('2018-06-01')%3B then precise the
    result you get.
-->

Unfortunately most of this code happens out of my control inside a library I'm using (spatie/laravel-data), which this previously used to work fine with in Carbon v2. I am aware this should probably be handled better by `::createFromTimestamp` or [HIDDEN].

I'm assuming this is due to added types on the `::rawCreateFromFormat` function or the addition of strict types on these files.

### Additional contract requirements

- For the reported `'U'` format, passing an integer Unix timestamp to `Carbon::createFromFormat` or `CarbonImmutable::createFromFormat` must successfully return the corresponding date object representing that timestamp.
