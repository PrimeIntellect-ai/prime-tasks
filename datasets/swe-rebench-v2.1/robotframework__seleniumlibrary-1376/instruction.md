It should be possible to configure Open Browser keyword to not always open a new browser.
Many times, when opening browser, there is need to open only one browser. But because depending how test are executed in Robot Framework, it is hard to find a single correct place for the `Open Browser` keyword. Most of the time, it is safer to run the `Open Browser` keyword from multiple levels in the suite structure, which will lead to many open browsers and loss in test execution time. There are also numerous other workarounds available.

Instead of the workarounds, it would be good to implement support for the `Open Browser` keyword  to open browser only once. If the the `Open Browser` keyword is configured to open browser only one time, it would act in same way as the `Go To` keyword.

The `alias` argument could act as a marker, should the existing browser be used or new one opened.

Currently if test does this:
```
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias |
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias |
```
It will open two browsers with same alias.

But after the change, this:
```
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias |
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias |
```
will open one browser. With the first `Open Browser` keyword run, it will open the browser normally and navigate to the `https://github.com/robotframework/SeleniumLibrary`. In the second first `Open Browser` keyword run, it navigate (again) to the `https://github.com/robotframework/SeleniumLibrary`.

Also this:
```
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias |
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Firefox | alias |
```
will open only one browser.

If different alias is used:
```
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias1 |
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome | alias2 |
```
it will open two browsers.

Also if alias is not defined
```
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome |
| Open Browser | https://github.com/robotframework/SeleniumLibrary | Chrome |
```
it will open two browsers.

There is small change that someone is misusing the `alias` argument and therefore this may cause problems for users. But because the problem should be easy to fix and the probability for that is quite low, implementing this is OK.

This idea is also presented in #701

### Additional contract requirements

- The `alias` argument is treated as if it was not given when its value is `None` or the string `None` (in any letter case). In that case a new browser is opened, exactly as when the argument is omitted.
