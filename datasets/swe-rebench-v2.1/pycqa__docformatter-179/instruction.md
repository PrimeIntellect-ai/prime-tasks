Doc formatter reformats correct docstring
with `docformatter 1.4`, command `docformatter --wrap-summaries 100 --wrap-descriptions 100`
the following docstring
```
"""hello yeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeet -v
"""
```
gets transformed to
```
"""hello yeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeet
-v."""
```
which is fine (correct), but then if I run docformatter again, the correct string incorrectly becomes
```
"""hello yeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeet.

-v.
"""
```
