Warn when users assign references to resources w/ `|version`
Reference assignments should not use `|` to indicate a version (see [zulip thread](https://chat.fhir.org/#narrow/stream/179177-conformance/topic/syntax.20of.20Reference.2Ereference.20with.20version/near/373027152)). It's valid for constraining reference types, but not assigning references to instances.

### Additional contract requirements

- The warning must include the exact message `Reference assignments should not include a version.` and the assignment's source location; for the tested assignment, this includes `File: Reference.fsh` and `Line: 5`.
- When exporting an assignment whose reference includes a version, ignore the version; the tested `managingOrganization` value must be `{ reference: 'Organization/org-id' }`.
