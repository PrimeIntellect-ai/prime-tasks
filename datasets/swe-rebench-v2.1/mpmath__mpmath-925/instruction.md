Support thousands separators for formatting fractional part of mpf
See https://github.com/python/cpython/issues/87790 and recent https://docs.python.org/3.14/library/string.html#format-specification-mini-language.

### Additional contract requirements

- A fractional-part thousands separator is requested by placing a comma (`,`) or an underscore (`_`) immediately after the precision in the format specification. For example, `f'{mp.mpf(0.0000004999):.9_f}'` is `'0.000_000_500'` and `f'{mp.mpf(0.0000004999):.9,f}'` is `'0.000,000,500'`.
- The public function `read_format_spec(format_spec)` in `mpmath.libmp.libmpf` returns a mapping that includes a string-valued `'frac_separators'` entry: the separator character (`,` or `_`) when one follows the precision, and `''` otherwise.
