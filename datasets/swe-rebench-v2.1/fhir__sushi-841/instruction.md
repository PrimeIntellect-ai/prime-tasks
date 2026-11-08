{CodeSystem name}|{version}#{code} "{display}" not working correctly
See Zulip: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Using.20Coding.20with.20.2Eversion/near/239067905

It appears that specifying the version in FSH concept syntax does not work when referencing a code from FSH-defined CodeSystems.  For example, this should work but does not:
```
CodeSystem: Test
* ^version = "1.0"
* #testcode "test-code" "A code for testing"


Instance: TestPatient
InstanceOf: Patient
* maritalStatus = Test|1.0#testcode
```

It results in:
> error Resolved value "Test|1.0" is not a valid URI.
