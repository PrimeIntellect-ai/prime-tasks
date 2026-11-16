Overwriting value on a Quantity
See this issue for full details: https://jira.hl7.org/browse/FHIR-28552.

When an author sets `value` on a Quantity, and then sets the Codeable properties on that Quantity as in the following:
```
* dosage.doseAndRate.doseQuantity.value = 250.0
* dosage.doseAndRate.doseQuantity = UCUM#mg "mg"
```
SUSHI overwrites the setting of `value` when setting the Codeable properties in the second line.
