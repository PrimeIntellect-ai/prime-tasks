ssn.it_IT.Provider generates SSNs shorter than 16 chars
* Faker version:  tested with 13.14.0,  15.3.3
* OS: Ubuntu 22.04

Generating an Italian SSN, when the last (or first) name returned by `person.it_IT.Provider` is 3 characters long and contains latin chars, the resulting string is shorter than expected (16 chars). In this scenario:

- string is not shorter than 3 chars, so it does not get padded
- latin char is neither a vowel nor a consonant, so it gets ignored

### Steps to reproduce

```
from unittest import mock

from faker import Factory

generator = Factory.create("it_IT")
generator.last_name = mock.MagicMock(return_value="Foà")

assert len(generator.ssn()) == 16

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
AssertionError
```

### Expected behavior

The length of generated SSN should be 16 characters. Latin chars should be translated into equivalent ASCII chars (A for À, E for È and É, etc.)

### Actual behavior

The length of generated SSN is 15 characters.
