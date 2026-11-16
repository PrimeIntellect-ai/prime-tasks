Handle "Age" when assigned FSHCode values
The line:
```
* condition.onsetAge = UCUM#a "years"
```
fails to set these values on `onsetAge` with the error:
```
error Cannot bind value set to Age; must be coded (code, Coding, CodeableConcept, Quantity), or the data types (string, uri).
  File: C:\Users\mkramer\Documents\GitHub\fhir-mCODE-ig\fsh\ExtendedExample1.fsh
  Line: 522
```
This is because `Age` is a specialization of `Quantity`, and we do not correctly handle that when a Coding type value is being assigned. We do have code to handle these specializations, since we correctly handle `Age` for the `64.0 'a'` syntax that can be used on a `Quantity`.
