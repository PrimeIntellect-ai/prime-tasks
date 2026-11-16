One-line block helper/components are not handled correctly
```hbs
{{#x-foo}}bar{{/x-foo}}
```
will report
```
Incorrect indentation for `x-foo` beginning at ('template.hbs'@ L1:C0).
Expected `{{/x-foo}}` ending at ('template.hbs'@ L1:C14) to be at an indentation of 0 but was found at 14.
```

Which is incorrect IMO.
