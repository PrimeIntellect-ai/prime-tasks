Issue with assigning values on sliced instances
I'm not exactly sure what is going wrong here, but when you make the following instance:
```
Alias: Abrechnung = http://fhir.abda.de/eRezeptAbgabedaten/StructureDefinition/Abrechnungszeilen

Instance:  TestInstanceSlicing
InstanceOf: Abrechnung
Usage:  #example
* status = #issued
* type.coding.system = "http://fhir.abda.de/eRezeptAbgabedaten/CodeSystem/invoice-typ"
* type.coding.code.value = "abrechnungszeilen"
* lineItem[0].chargeItemCodeableConcept = http://fhir.de/CodeSystem/ifa/pzn#1
```
which is an instance of this this profile: https://simplifier.net/erezeptabgabedaten/abrechnungszeilen-duplicate-2 (which I've also attached as a text file), you get errors like:
```
error Cannot assign [object Object] to this element; a different Coding is already assigned: {"system":"http://TA1.abda.de"}.
  File: /input/fsh/abrechnungszeilen.fsh
  Line: 9
```

At the very least, the [object Object] is no good, but I'm also pretty sure this error should not exist at all. But this does require further investigation.

[Abrechnungszeile.txt](https://github.com/FHIR/sushi/files/5925759/Abrechnungszeile.txt)

### Additional contract requirements

When assigning a value to an element with child slicing, a value fixed on a particular slice applies to that slice; it must not by itself reject an assignment to the unsliced parent element. An assignment matching at least one applicable slice is allowed, even if it conflicts with another slice's fixed value. An unmatched value is allowed by open slicing, but is rejected with an error reported by closed slicing. When a rejected assignment has an object value, its diagnostic must not render that value as `[object Object]`.
