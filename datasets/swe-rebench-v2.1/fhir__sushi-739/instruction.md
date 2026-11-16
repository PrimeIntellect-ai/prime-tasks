SUSHI repeats mappings/invariants in differential
Some arrays in FHIR differentials are intended to be _additive_ -- meaning that they don't _replace_ the array in the snapshot, but rather append to it.  I believe this is the case for invariants and mappings (although we should confirm by testing the behavior of the IG publisher).

If this is the case, SUSHI should be fixed such that it only generates the _additional_ items for these arrays in the differential (rather than repeating all the existing items).

### Additional contract requirements

FHIR treats ElementDefinition invariant constraints and mappings as additive: additional entries extend those inherited from the snapshot rather than replacing them. A generated differential must include newly introduced constraints and mappings, and must not repeat entries already present in the snapshot. When there are no new entries, the differential may omit the corresponding property or represent it as an empty array.
