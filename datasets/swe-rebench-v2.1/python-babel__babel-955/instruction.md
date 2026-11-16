format functions fail on infinity
``` python
>>> format_decimal(Decimal('Infinity'))
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "babel/numbers.py", line 165, in format_decimal
    return pattern.apply(number, locale)
  File "babel/numbers.py", line 563, in apply
    self.frac_prec[1]))
  File "babel/numbers.py", line 380, in bankersround
    a, b = split_number(value)
  File "babel/numbers.py", line 330, in split_number
    for i in range(-exp):
TypeError: bad operand type for unary -: 'str'
```

### Additional contract requirements

Formatting infinity must not raise an exception. The formatted result uses the
locale's infinity symbol, with the sign and currency symbol placed as shown:

```python
>>> format_decimal(Decimal('Infinity'), locale='en_US')
'∞'
>>> format_decimal(Decimal('-Infinity'), locale='en_US')
'-∞'
>>> format_compact_decimal(Decimal('Infinity'), locale='en_US', format_type='short')
'∞'
>>> format_compact_decimal(Decimal('-Infinity'), locale='en_US', format_type='short')
'-∞'
>>> format_currency(Decimal('Infinity'), 'USD', locale='en_US')
'$∞'
>>> format_currency(Decimal('-Infinity'), 'USD', locale='en_US')
'-$∞'
```
