Nested Choice elements in differential can cause IG Publisher to fail
See this thread https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Mapping.20value.5Bx.5D.2Eproperty for full details. When a Profile changes nested elements of an extension as in the following example:
```
Profile: IssueProfile
Parent: http://hl7.org/fhir/StructureDefinition/Basic
Id: issue-report
Title: "IssueReport"
* extension contains IssueExtension named issue 1..1 MS
* extension[issue].valuePeriod.start MS

Extension: IssueExtension
Id: issue-extension
Title: "IssuePeriod"
* ^context.expression = "Basic"
* value[x] only Period
* valuePeriod 1..1
```
This can cause the following error in snapshot generation:
```
Error in snapshot generation: The profile http://hl7.org/fhir/sushi-test/StructureDefinition/issue-report has 1 element in the differential (id: Basic.extension:issue.valuePeriod.start) that don't have a matching element in the snapshot: check that the path and definitions are legal in the differential (including order)
```
This could potentially be a bug in the IG Publisher, or it could be an issue in how we are representing paths in our differentials, or this could be something that we are allowing to happen in SUSHI that actually is not valid. Regardless, this needs further investigation.

### Additional contract requirements

When a StructureDefinition differential is generated, a slice element must be included in the differential whenever the slice itself or any of its descendant elements differs from the original definition. Specifically:

- For an element that has a `sliceName`, `ElementDefinition.hasDiff()` must return `true` if the element itself changed or if any of its descendant elements changed, and `false` if neither the slice nor any of its descendants changed.
- The generated differential must contain an entry for such a slice (including its `id`, `path`, and `sliceName`) in addition to the entry for the changed descendant. The entry for the changed descendant contains its `id`, `path`, and the properties that changed.

This requirement applies to slices in general, not only to the nested Choice extension example above.
