Issues w/ cardinality counting and re-slices
SUSHI seems to struggle with cardinality counting on instances of profiles with re-slicing.  There are two issues:
* SUSHI infers the wrong minimum cardinality for the element that is sliced in the profile
* SUSHI does not recognize re-slices in an instance as fulfilling cardinality of the parent slice

Given this example (https://fshschool.org/FSHOnline/#/share/3opCADp):
```
Alias: HeartRate = http://hl7.org/fhir/StructureDefinition/heartrate
Alias: LOINC = http://loinc.org

Profile: MyBundleProfile
Parent: Bundle
* type = #collection
* entry ^slicing.discriminator.type = #type
* entry ^slicing.discriminator.path = "resource"
* entry ^slicing.rules = #open
* entry contains observations 1..*
* entry[observations].resource only Observation
* entry[observations] ^slicing.discriminator.type = #profile
* entry[observations] ^slicing.discriminator.path = "resource"
* entry[observations] ^slicing.rules = #open
* entry[observations] contains heartrate 1..1 MS
* entry[observations][heartrate].resource only HeartRate

Instance: MyBundleInstance
InstanceOf: MyBundleProfile
* entry[observations][heartrate].resource = MyHeartRate

Instance: MyHeartRate
InstanceOf: HeartRate
* status = #final
* subject = Reference(MyPatient)
* effectiveDateTime = "2021-01-28"
* valueQuantity = 44 '/min' "beats/min"

Instance: MyPatient
InstanceOf: Patient
* name.given = "Bob"
```

SUSHI produces these errors:
```
error Element Bundle.entry has minimum cardinality 2 but occurs 1 time(s).
  Line: 18 - 20

error Element Bundle.entry:observations has minimum cardinality 1 but occurs 0 time(s).
  Line: 18 - 20
```

Reported on Zulip: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Slicing.20on.20slices.3F
