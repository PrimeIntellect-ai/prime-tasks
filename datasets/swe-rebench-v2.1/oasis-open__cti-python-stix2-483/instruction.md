Implement `is_sdo`, `is_sco` utility functions
These are checks we find ourselves performing frequently.

### Additional contract requirements

`stix2.utils.is_sdo` and `stix2.utils.is_sco` accept a STIX type name, a STIX ID, or a mapping with a `type` field. Each accepts an optional STIX version; when omitted, the library's default version is used. Type names and IDs are checked against that version. For mappings, the represented version is inferred from the mapping, and the predicate returns false if it does not match the selected version. The predicates return true only when the value represents, respectively, a STIX Domain Object or a STIX Cyber Observable.
