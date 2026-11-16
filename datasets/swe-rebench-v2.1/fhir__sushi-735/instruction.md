Extension use in arrays: Cannot convert undefined or null to object
This works fine:
```
* name[0].given[0] = "John"
* name[0].given[1] = "Bob"
* name[0].given[0].extension[nameQualifier].valueCode = #CL
```
This gives "SUSHI encountered the following unexpected error: Cannot convert undefined or null to object":
```
* name[0].given[0] = "John"
* name[0].given[1] = "Bob"
* name[0].given[1].extension[nameQualifier].valueCode = #CL
```
and this is the extension:
```
Profile: SEBaseHumanName
Parent: http://hl7.org/fhir/StructureDefinition/HumanName
Description: "This profile provides the use of Swedish middlename as extensions and is used in the base Patient profile"
* insert SEStandardRuleSet
* extension contains SEBaseMiddleNameExtension named middleName 0..1
* extension contains SEBaseOwnFamilyExtension named ownFamily 0..1
* given.extension contains http://hl7.org/fhir/StructureDefinition/iso21090-EN-qualifier named nameQualifier 0..1
* given.extension[nameQualifier].valueCode from SEBaseNamePartQualifierVS (required)
```
Any thoughts? If the extension is used on both given:s it also works but that is not what is intended.
