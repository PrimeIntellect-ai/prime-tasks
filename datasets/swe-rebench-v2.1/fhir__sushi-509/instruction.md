Extra Extensions on Instances
See https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/extensions.20on.20repeating.20elements for more details. To recreate this bug, you can use the following full example:
```
Instance: PatInstance
InstanceOf: MyPatient
* generalPractitioner[0] = Reference(drwelby)       //the GP
* generalPractitioner[0].display = "Dr Marcus Welby"

* generalPractitioner[1] = Reference(gp-org1)       //the GP Practice
* generalPractitioner[1].display = "Good Health Medcial Centre"
* generalPractitioner[1].extension[edi-address].valueCode = #F
* generalPractitioner[1].extension[gp-practice-enrollment-date].valueBoolean = true

Profile: MyPatient
Parent: Patient
* generalPractitioner only Reference(Practitioner | Organization)
* generalPractitioner.extension contains
    http://hl7.org/fhir/us/core/StructureDefinition/us-core-birthsex named edi-address 0..1 and
    http://hl7.org/fhir/us/core/StructureDefinition/us-core-direct named gp-practice-enrollment-date 0..1
```

You should see that there are extraneous extension elements added to `generlPractitioner[0]`. This looks like it is happening in the `setImpliedPropertiesOnInstance` function, so that may be a good place to start investigating this.
