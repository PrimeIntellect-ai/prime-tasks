Quantity with units: Zero (0) value is omitted in instances
Hi,

sushi v2.1.1 does not write a valueQuantity.value 0 to an instance when using the "short syntax":

Consider the following 2 examples:
```
Alias: $loinc = http://loinc.org
Alias: $ucum = http://unitsofmeasure.org

Instance: MyObservationValid
InstanceOf: Observation
* status = #final
* code = $loinc#8867-4 "Alcoholic drinks per day"
* valueQuantity
  * system = $ucum
  * value = 0
  * code = #/d
  * unit = "PerDay"

Instance: MyObservationInvalid
InstanceOf: Observation
* status = #final
* code = $loinc#74013-4 "Alcoholic drinks per day"
* valueQuantity = 0 '/d' "PerDay"
```
Both instances should be the same (as of my understanding), but the first instance (MyObservationValid) is translated by sushi to (excerpt):
``` json
  "valueQuantity": {
    "system": "http://unitsofmeasure.org",
    "value": 0,
    "code": "/d",
    "unit": "PerDay"
  }
```

Whereas the second instance (MyObservationInvalid) is translated to:
``` json
  "valueQuantity": {
    "code": "/d",
    "system": "http://unitsofmeasure.org",
    "unit": "PerDay"
  }
```
i.e. omitting the value (this happens only with value of 0).
