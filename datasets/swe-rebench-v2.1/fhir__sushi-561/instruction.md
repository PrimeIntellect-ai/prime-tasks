SUSHI does not support pattern[x]/fixed[x] w/ inline instances
The following should be supported, but currently is not:
```
Instance: USPostalAddress
InstanceOf: Address
Usage: #inline
* type = #postal
* country = "US"

Profile: USPatient
Parent: Patient
* address = USPostalAddress
```

As written, this should create the following attribute in the `USPatient` profile's `Patient.address` element:
```json
"patternAddress": {
  "type": "postal",
  "country": "US"
}
```

Unless I'm mistaken, supporting something like the FSH above is the _only_ way to get a `patternAddress` into an element without introducing a syntax that allows `{` `}` objects in FSH.

### Additional contract requirements

- When a profile rule references a missing instance, skip the rule and log an error containing `Cannot find definition for Instance: FakeInstance. Skipping rule.`

- When a profile rule references an inline instance with exact semantics (`(exactly)`), the target element must contain the instance fields in its typed `fixed[x]` value. For an Address element, that value is exposed as `fixedAddress`.
