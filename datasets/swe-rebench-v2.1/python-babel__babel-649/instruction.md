parse_decimal is not works correctly when space symbol as grouping
```
from babel.numbers import format_decimal

format_decimal(12345.123, locale='ru')

'12\xa0345,123'
```
```
from babel.numbers import parse_decimal

parse_decimal('12 345,123', locale='ru')

babel/numbers.py", line 605, in parse_decimal
    .replace(get_decimal_symbol(locale), '.'))
decimal.InvalidOperation: [<class 'decimal.ConversionSyntax'>]
babel.numbers.NumberFormatError
```

There is a problem because ' '.replace('\xa0', '.') is not replace space to dot.
