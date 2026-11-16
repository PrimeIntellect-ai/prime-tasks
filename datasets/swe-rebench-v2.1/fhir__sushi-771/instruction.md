SUSHI does not export extensions correctly when setting extension on primitive using caret rule
Easier to explain by example ([FSH Online](https://fshschool.org/FSHOnline/#/share/36L5EiC)):
```
Profile: MyProfile
Parent: Patient
// This serializes correctly:
* ^extension[MyBooleanExtension].valueBoolean = true
// But this does not serialize correctly:
* ^status.extension[MyBooleanExtension].valueBoolean = true

Extension: MyBooleanExtension
* value[x] only boolean
```

The first extension gets serialized correctly:
```json
{
  "url": "http://example.org/StructureDefinition/MyBooleanExtension",
  "valueBoolean": true
}
```

The second does not:
```json
{
  "_sliceName": "MyBooleanExtension",
  "url": {
    "assignedValue": "http://example.org/StructureDefinition/MyBooleanExtension",
    "_primitive": true
  },
  "valueBoolean": {
    "assignedValue": true,
    "_primitive": true
  }
}
```
