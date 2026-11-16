Type Integer Maximum constraint validation message is not correct
```yaml
number:
  type: integer
  minimum: 1
  maximum: 2147483648
  exclusiveMaximum: true
```

When number is equal to 2147483648, I get this validation message:

`Keyword validation failed: Value 2147483648 must be less or equal to 2147483648`

Validation is good but the message is wrong, it should be `less than 2147483648`

Messages when using exclusiveMaximum true/false should be interchanged.
