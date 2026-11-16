identities that have a base identity are not sorted
In YANG when a set of individual identities have a common base identity, these individual identities are gathered under the base, but their order is non deterministic, as they are extracted from a Go map.

This has 2 negative consequences
* YGOT `generate` command can produce a different JSON schema each time it it run because the order of identities changes, even though there are no real changes
* the order of these identities will be different to the enum entries in the generated code (which are sorted alphabetically). Therefore is is not possible to reference enums in the generated code by the order of the identities in the JSON schema
