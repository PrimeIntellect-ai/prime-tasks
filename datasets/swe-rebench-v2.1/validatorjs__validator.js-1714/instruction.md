isPassportNumber isnot  exactlly
**Describe the bug**
isPassportNumber isnot  exactlly  for countryCode with CN


**Examples**
1.My passport no is start with ED followed by 7-digits  it's error
you can change
[HIDDEN]

2.Is any code can be HK、TW  passport validator？？


**Additional context**
Validator.js version: 13.6.0
Node.js version: v14.16.0
OS platform: macOS

### Additional contract requirements

- For country code `CN`, `isPassportNumber` must accept a passport number that begins with `ED` followed by exactly seven digits (for example `ED1234567`).
- For country code `CN`, a passport number that begins with `ED` followed by a different number of digits (for example eight digits or six digits) must be rejected.
- Existing `CN` passport numbers keep their current results: a `G` followed by eight digits and an `E` followed by eight digits remain valid.
