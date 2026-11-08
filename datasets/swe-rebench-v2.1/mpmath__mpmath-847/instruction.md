Support for '%' presentation type in `mpf.__format__`
I've been working on these presentation types, to complete the set.
[HIDDEN]

'n' is a lot trickier, since some locales may be difficult to program.
For instance,
```python
>>> import locale
>>> locale.setlocale(locale.LC_ALL, 'en_IN.utf8')
>>> print('{:.10n}'.format(100000.25))
1,00,000.25
```
Would a partial implementation of 'n' (i.e., only care about thousands and decimal separators) be useful or should we not bother at all with it?

### Additional contract requirements

- Formatting an `mpf` with the `%` presentation type must display its value as a percentage: the displayed numeric value represents 100 times the input and is followed by a percent sign.
