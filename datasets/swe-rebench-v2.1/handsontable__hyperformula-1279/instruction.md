Function IFS
### Can you support function IFS
I see that IFS is [supported by excel](https://support.microsoft.com/en-us/office/ifs-function-36329a26-37b2-467c-972b-4a39bd951d45) but not by [hyperformula](https://hyperformula.handsontable.com/guide/built-in-functions.html#list-of-available-functions), I am curious why is that and can it be supported.

Thank you!
Makarand

### Additional contract requirements

IFS evaluates condition/value pairs from left to right and returns the value paired with the first true condition. If no condition is true, it returns a #N/A error. An IFS call must contain at least one complete condition/value pair; calls with no pairs or an incomplete pair are rejected.
