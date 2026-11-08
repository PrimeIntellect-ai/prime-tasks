Fixed codes don't account for parent elements w/ pattern[x]
Currently, when the user tries to fix a value, we check the Structure Definition to see if that value has already been set on the element by a pattern or fixed field. However, the pattern field can be used to specify which values children of the element must have. We do not account for this. For example, if Patient.maritalStatus has a field like:

```
"patternCodeableConcept": {
  "coding": [
    { "code": "foo" }
  ]
}
```

We currently still allow the user to re-fix the value of Patient.maritalStatus.coding[0].code. This behavior is incorrect, and should be fixed to not allow this value to be fixed to something other than "foo"
