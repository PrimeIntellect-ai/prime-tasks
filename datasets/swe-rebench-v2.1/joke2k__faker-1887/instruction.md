Feature: Elector code for es_MX ssn provider
* Faker version: 18.11.2
* OS: NA

The National Electoral Institute in Mexico issues a unique identifier code for electors, it would be great if the library could fake those.

### Steps to reproduce

NA

### Expected behavior

```python
>>> fake.elector_code()
"GLVLMR80070509M900"
```

### Actual behavior

It's not implemented 😅

### Additional contract requirements

- `fake.elector_code()` can be called with no arguments and returns a fabricated 18-character elector code in the same layout as the expected example: six uppercase letters, six digits for the birth date (YYMMDD), two digits for the entity code, a gender letter that is either `H` or `M`, and three digits.
