FHIR rules for name and id should be enforced
Currently SUSHI allows `name` and `id` to be any sequence of non-whitespace characters.  FHIR, however, is more specific:

* name: `[A-Z]([A-Za-z0-9_]){0,254}` (http://hl7.org/fhir/R4/structuredefinition-definitions.html#StructureDefinition.name)
* id: `[A-Za-z0-9\-\.]{1,64}`  (http://hl7.org/fhir/R4/datatypes.html#id)

We should probably catch names/ids that violate these rules and report them as errors in SUSHI.  While we could update the ANTLR grammar to reflect these requirements, it might be more user-friendly to keep the grammar as-is and do the check in code.  Grammar violations make ugly and sometimes-confusing error messages.

### Additional contract requirements

When SUSHI exports a code system, structure definition, value set, or instance, it must validate any `id` against `[A-Za-z0-9\-\.]{1,64}` and any `name` against `[A-Z]([A-Za-z0-9_]){0,254}`. A value that does not match its applicable pattern must be reported as an error in SUSHI.
