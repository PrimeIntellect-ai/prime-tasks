Allow range validator to refer to a variable
The range validator requires the raw numerical value in quotes. It should let it be a variable name in scope as well (or instead).

### Additional contract requirements

- A failed range validation must report the error code `"range"`.
