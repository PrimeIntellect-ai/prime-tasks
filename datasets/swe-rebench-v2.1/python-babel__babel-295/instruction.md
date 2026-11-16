CLDR parser is probably broken (invalid plural forms)
While trying to import data from CLDR with babel I encountered some issues which I would like to share.

- Version 2.1.1 installed with pip returns invalid number of plurals at least for Turkish (tr) and Hungarian (hu). According to babel, both languages have only one form, while [in fact they have two](http://www.unicode.org/cldr/charts/28/supplemental/language_plural_rules.html#hu): `one` and `other`.
- Version installed from git fixes the issue with Hungarian and Turkish, but gettext strings returned for at least Russian and Polish, contain forbidden variables. While gettext only accepts `n` as a variable, Babel rules contain `i` and `v` vars.

Attaching the gist with my testing script and my output: https://gist.github.com/imankulov/866660acdd90cb4004c7

Tested with following interpreter

```
Python 2.7.10 (default, Sep 23 2015, 04:34:14)
[GCC 4.2.1 Compatible Apple LLVM 7.0.0 (clang-700.0.72)] on darwin
```

I would appreciate any input. Thanks!
