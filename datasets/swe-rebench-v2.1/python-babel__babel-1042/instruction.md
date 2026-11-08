parse_decimal raises error for decimals with thousand separator and trailing zeroes
# Bug report

`parse_decimal` raises a surprising NumberFormatError when parsing numbers with thousand separator and non-zero decimals but trailing zeros, when strict mode is set:
```
In [1]: parse_decimal('3,400.60',locale='en',strict=True)`
---------------------------------------------------------------------------`
NumberFormatError                         Traceback (most recent call last)
<ipython-input-6-ccc56249e0c2> in <module>
----> 1 parse_decimal('3,400.60', locale='en', strict=True)

~/iit_repos/hrreport/.tox/test/lib/python3.10/site-packages/babel/numbers.py in parse_decimal(string, locale, strict)
    765                     ), suggestions=[proper])
    766                 else:
--> 767                     raise NumberFormatError((
    768                         "%r is not a properly formatted decimal number. Did you mean %r? Or maybe %r?" %
    769                         (string, proper, proper_alt)

NumberFormatError: '3,400.60' is not a properly formatted decimal number. Did you mean '3,400.6'? Or maybe '3.4006'?`
```
Working variants:
```
In [2]: parse_decimal('3400.60', locale='en', strict=True)
Out[2]: Decimal('3400.60')

In [3]: parse_decimal('3,400.6', locale='en', strict=True)
Out[3]: Decimal('3400.6')

In [4]: parse_decimal('3,400.00', locale='en', strict=True)
Out[4]: Decimal('3400.00')
```
It is surprising and inconsistent that the presence or absence of the thousand separator should effect the result so.

# Your environment

- CPython versions tested on: 3.11.0, 3.10.6
- Babel versions tested on: 2.10.3, 2.11.0
- locales tested: 'en', 'de'
- Operating system and architecture: `5.15.0-52-generic #58-Ubuntu x86_64 GNU/Linux` (up-to-date Ubuntu 22.04 LTS)

# Additional Information
Thanks for the great library!
