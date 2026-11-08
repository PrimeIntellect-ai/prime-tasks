Very small decimal with disabled decimal_quantization
How to reproduce:
```
from babel.numbers import format_decimal
from decimal import Decimal

format_decimal(Decimal('0.00000011'), locale='en', decimal_quantization=False)
```
Result:
```
  File "babel/numbers.py", line 386, in format_decimal
    number, locale, decimal_quantization=decimal_quantization)
  File "babel/numbers.py", line 857, in apply
    number = self._quantize_value(value, locale, frac_prec)
  File "babel/numbers.py", line 930, in _quantize_value
    self._format_frac(b or '0', locale, frac_prec))
  File "babel/numbers.py", line 937, in _format_frac
    if max == 0 or (min == 0 and int(value) == 0):
ValueError: invalid literal for int() with base 10: '1E-7'
```
My solution:
```
def _quantize_value(self, value, locale, frac_prec):
    quantum = get_decimal_quantum(frac_prec[1])
    rounded = value.quantize(quantum)
    [HIDDEN]
    [HIDDEN]
    [HIDDEN]
```

### Additional contract requirements

- Formatting the reported very small Decimal with `decimal_quantization=False` must produce a locale-formatted result that preserves its fractional value rather than raising the reported `ValueError`.
