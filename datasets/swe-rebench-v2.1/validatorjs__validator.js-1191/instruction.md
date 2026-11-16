Add stricter Ecuador phone number validation
Following the comments on #1187, certain digit combinations are not valid. According to the [ITU document about Ecuador National Numbering plans](https://www.itu.int/dms_pub/itu-t/oth/02/02/T020200003D0001PDFE.pdf) there are a couple of missing rules:

- 9 digits numbers are only valid if the first digit is 9.
- Cellphone numbers start with a network code between 92 and 99, so cellphone numbers starting with 90 and 91 are invalid

A PR is coming shorty to address this issue.
