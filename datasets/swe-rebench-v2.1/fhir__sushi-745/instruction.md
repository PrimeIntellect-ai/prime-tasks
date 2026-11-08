Duplicate meta.profile values when profiles assign meta.profile value
When a profile assigns a meta.profile value (meaning all instances must have it), SUSHI will generate instances that have the profile value twice.  This is likely because the instance exporter generates it based on the fixed value rule, but also generates it automatically based on the `InstanceOf:` metadata.

This was seen in the carin-bb IG, but can be replicated with [this FSH code](https://fshschool.org/FSHOnline/#/share/2LQcQms):
```
Profile: MyPatientAbstract
Parent: Patient
Id: MyPatientAbstract
Title: "My Patient Abstract"
Description: "Simple example test Abstract"
* meta 1..1 MS
* meta.profile 1..* MS

* meta.profile ^slicing.discriminator.type = #pattern
* meta.profile ^slicing.discriminator.path = "$this"
* meta.profile contains supportedPatientProfile 1..1 MS



Profile: MyPatient
Parent: MyPatientAbstract
Id: MyPatient
* meta.profile[supportedPatientProfile] = Canonical(MyPatient)


Instance: MyPatientInstance
InstanceOf: MyPatient
Usage: #example
* name[0].family = "LastName"
```

Resulting in this instance:
```json
{
  "resourceType": "Patient",
  "id": "MyPatientInstance",
  "meta": {
    "profile": [
      "http://example.org/StructureDefinition/MyPatient",
      "http://example.org/StructureDefinition/MyPatient"
    ]
  },
  "name": [
    {
      "family": "LastName"
    }
  ]
}
```
