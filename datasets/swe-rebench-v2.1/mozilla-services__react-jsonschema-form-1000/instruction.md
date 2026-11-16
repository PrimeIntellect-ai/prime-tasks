Regression for multipleOf precision issue after change to ajv
### Prerequisites

- [x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [ ] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

I believe that after the change to use ajv the issue where "multipleOf" is set to a decimal and fails validation due to floating point precision has appeared again. The original ticket to fix it was #671

[HIDDEN]

### Steps to Reproduce

In the playground set the schema to:
```
{
  "type": "object",
  "properties": {
    "price": {
      "title": "Price per task ($)",
      "type": "number",
      "multipleOf": 0.01,
      "minimum": 0
    }
  }
}
```

set the value in the form to 0.14 and the field will display an error "should be multiple of 0.01".

### Version
1.x.x

### Additional contract requirements

- For decimal `multipleOf` constraints, mathematically exact multiples must not be rejected solely because of floating-point precision. In the reported example, `0.14` with `multipleOf: 0.01` must validate successfully.
