Slicing anomaly in instance of US Core Organization
There something wrong with the attached example.

[Organization-mCODEOrganizationExample01.json.txt](https://github.com/FHIR/sushi/files/4098514/Organization-mCODEOrganizationExample01.json.txt)

The IG Publisher complains that:

`Practitioner | error | Unrecognised property '@identifier:NPI'`

Here's the FSH - it is pretty straightforward:

```
Instance: mCODEOrganizationExample01
InstanceOf: USCoreOrganization
* id = "mCODEOrganizationExample01"
* identifier[NPI].value = "1265714091"
* active = true
* name = "Foundation Medicine"
* contact.telecom.system = #phone
* contact.telecom.value = "617-418-2200"
* address.line = "150 Second Street"
* address.city = "Cambridge"
* address.state = "MA"
* address.postalCode = "02141"
* address.country = "USA"
```

### Additional contract requirements

An explicit instance assignment to a named slice must be exported as an ordinary element in the resource property’s repeated data, not as a separate property labeled with the slice name. When the assignment activates a slice, fixed or patterned values constrained on that slice must be retained in the exported element alongside the assigned value.
