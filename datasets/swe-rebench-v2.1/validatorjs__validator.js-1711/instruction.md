isDate(): Format 'DD.MM.YYYY' does not pass isValidFormat
**Describe the bug**

I can't set DD.MM.YYYY format, because function isValidFormat returns false.
I can't go with workaround like `isDate("19.08.2021", { format: 'DD/MM/YYYY', delimiters: ["/", "."] });`  because it approves dates with "/" delimeter


**Examples**
`isDate("19/08/2021", { format: 'DD.MM.YYYY', delimiters: ["."], strictMode: true  });` returns false

**Additional context**
Validator.js version: 13.6.1
Node.js version: 12.15.0
OS platform: [linux]
