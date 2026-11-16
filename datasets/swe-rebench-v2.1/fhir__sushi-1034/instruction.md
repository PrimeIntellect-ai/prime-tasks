SUSHI should allow extensions on primitives to satisfy cardinality
Reported by Julian Sass on zulip [here](https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Error.20extension.20on.20element.20w.2F.20min.201.20cardinality):

SUSHI compiler throws an error for instances that use an extension like data-absent-reason on elements that have a min 1 cardinality defined in a profile. E.g.:

```
Profile: MyProcedure
Parent: Procedure
* performed[x] 1..1

Instance: my-procedure
InstanceOf: MyProcedure
* status = #not-done
* subject = Reference(Patient/example)
* performedDateTime.extension.url = "http://hl7.org/fhir/StructureDefinition/data-absent-reason"
* performedDateTime.extension.valueCode = #not-performed
```

produces
> error Element Procedure.performed[x] has minimum cardinality 1 but occurs 0 time(s).

I think the error should not be triggered.

https://fshschool.org/FSHOnline/#/share/34xsyMF
