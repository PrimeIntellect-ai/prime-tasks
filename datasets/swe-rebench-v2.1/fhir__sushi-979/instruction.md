SUSHI emits spurious warnings on use of soft indexing
SUSHI 2.2.2 introduced a bug that causes SUSHI to log warnings on many valid uses of soft indexing.  For example, the following causes a number of warnings:

```
Instance: MyPatient
InstanceOf: Patient
* name[+].use = #usual
* name[=].family = "Smith"
* name[=].given = "John"
* name[+].use = #old
* name[=].family = "Schnidt"
* name[=].given[+] = "John"
* name[=].given[+] = "Jacob"
* name[=].given[+] = "Jingle"
* name[=].given[+] = "Heimer"
* name[=].period.end = "1960"
* name[+].use = #official
* name[=].family = "Smith"
* name[=].given[+] = "John"
* name[=].given[+] = "Jacob"
* name[=].given[+] = "Jingleheimer"
* name[=].period.start = "1960-01-01"
* name[+].use = #nickname
* name[=].family = "Smith"
* name[=].given = "Jack"
```

Since the above is completely valid, there should be no warnings.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/SUSHI.202.2E2.2E2/near/264514577
