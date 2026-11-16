References to codes defined in locally-defined code system cause IG Pub error
I tried to define a local code system:
````
CodeSystem:  AJCCFairUse
Title: "AJCC Fair Use"
Description: "A small local subset of AJCC staging codes for example purposes."
* #3C
* #cM0
* #cT3
* #cN3
* #pM0
* #pT3
* #pN3
```
and then referenced it in an instance like this:

`* valueCodeableConcept = AJCCFairUse#3C "IIIC"`

That didn't work because the IG Pub complained that you must use a URL for a code system, not a local name.

So I tried this:

`Alias:   FairUse = http://hl7.org/fhir/us/mcode/CodeSystem/AJCCFairUse`

and then tried to reference it in an instance like this:

`* valueCodeableConcept = FairUse#3C "IIIC"`

but that didn't work either. The IG Pub complained "Unknown Code System 'http://hl7.org/fhir/us/mcode/CodeSystem/AJCCFairUse'", and "URL value 'http://hl7.org/fhir/us/mcode/CodeSystem/AJCCFairUse' does not resolve"

So I'm wondering how one an define a code system in FSH and use codes from that system in the same FSH Tank.

Sorry I can't provide a more complete example because I pulled back my change.
