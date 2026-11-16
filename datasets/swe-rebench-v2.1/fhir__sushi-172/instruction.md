Set properties on instance from pattern[x] on parent element
When we create an instance, we copy over fixed and pattern values from the Structure Definition onto the instance. However, if an element's value is set by a pattern on that element's parent, the element does not get fixed, because we only account for fixed values that are directly on the element, not for pattern values that may be present on parents of the element. As an example, see the below:
```
* identifier[NPI].value = "1265714091"
// workaround for https://github.com/FHIR/sushi/issues/148: "Pattern in StructureDefinition not reflected in Instance" opened 1-25-2020 by MK
* identifier[NPI].system = "http://hl7.org/fhir/sid/us-npi"   // although URI is not a supported type in FSH yet, apparently you can get away with giving the URI as a string, and the json comes out correctly.
```
If we remove the workaround (i.e., delete the line fixing the system) then the system doesn't get set in the example at all:
```
  "identifier": [
    {
      "value": "1265714091"
    }
  ],
```
Although indentifier[NPI] slice is 0..1, identifier[NPI].system is 1..1 -- so according to our basic rules, it should be set since we're going to identifier[NPI] to set the value. The system element needs to not only be checked to see if it has any direct fixed values, it also needs to be checked to see if parents fix it as well. This is similar to https://github.com/FHIR/sushi/issues/84, and it is likely that solving this issue will make that issue easy to solve, but they are not quite duplicates.
