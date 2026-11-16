Warn on empty string
FHIR indicates that `string` values should have at least one non-whitespace character (see: https://build.fhir.org/datatypes#string).  SUSHI should warn users when they assign an empty string.

If this is complex to do for arbitrary assignments, we should at least do it for the major metadata keywords (`Title:`, `Description:`, etc) -- especially since the VS Code snippets produce empty strings for these by default.

See: https://chat.fhir.org/#narrow/stream/179252-IG-creation/topic/Miss.20leading.20QA.2Ehtml.20results/near/282548095

### Additional contract requirements

- When exporting a CodeSystem, ValueSet, Instance, Profile, Extension, Logical, or Resource with both an empty title and an empty description, emit exactly two warnings, with the title warning first and the description warning second. The warning text must use these formats, substituting the definition's name for `{name}`: `Code system {name} has a title field that should not be empty.` and `Code system {name} has a description field that should not be empty.`; `Value set {name} has a title field that should not be empty.` and `Value set {name} has a description field that should not be empty.`; `Instance {name} has a title field that should not be empty.` and `Instance {name} has a description field that should not be empty.`; `Profile {name} has a title field that should not be empty.` and `Profile {name} has a description field that should not be empty.`; `Extension {name} has a title field that should not be empty.` and `Extension {name} has a description field that should not be empty.`; `Logical {name} has a title field that should not be empty.` and `Logical {name} has a description field that should not be empty.`; `Resource {name} has a title field that should not be empty.` and `Resource {name} has a description field that should not be empty.`
