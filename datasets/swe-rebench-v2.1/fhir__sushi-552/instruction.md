Can't set age value in instance using quantity syntax
Attempting this (on instance of `FamilyMemberHistory`):
```
* condition.onsetAge = 30.0 'a'
```
Results in this:
```
error Cannot fix number value: 30. Value does not match element type: Age
```

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Instance.20age
