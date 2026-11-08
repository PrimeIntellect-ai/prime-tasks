Annoying white space dependency

THis is OK:   Alias:   $OrgType = http://terminology.hl7.org/CodeSystem/organization-type

This is NOT:  Alias:   $OrgType= http://terminology.hl7.org/CodeSystem/organization-type

### Additional contract requirements

- When an Alias declaration is missing at least one space before or after `=`, report `Alias declarations must include at least one space both before and after the '=' sign` and include `File: <filename>` and `Line: <line>` in the error.
- For assignment rules, including caret rules, missing at least one space before or after `=`, report `Assignment rules must include at least one space both before and after the '=' sign`. For mapping rules missing at least one space before or after `->`, report `Mapping rules must include at least one space both before and after the '->' operator`. For a rule starting with `*` without a following space, report `Rules must start with a '*' symbol followed by at least one space`. Include `File: <filename>` and `Line: <line>` in these errors.
- - For each of these malformed inputs, the last logged error must contain its specified diagnostic before `File: <filename>` and `Line: <line>`, in that order.
