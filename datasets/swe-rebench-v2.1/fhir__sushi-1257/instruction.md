SUSHI should detect when ValueSets are used as contained resources and create the proper references
SUSHI should detect when a value set is used as a contained resource and use the correct reference format (with a `#`) when that contained value set is referenced. Right now, if the value set is added as a contained resource and the value set is used in a reference (e.g. `Reference(MyValueSet)`), the reference does not reference the inline resource and creates a regular reference that points to the standalone ValueSet resource (e.g. `"reference": "EgValueSet"`). Instead, it should reference the contained resource using the `#` reference format (e.g. `"reference": "#MyValueSet"`).

A simple FSH Online example demonstrates this: https://fshschool.org/FSHOnline/#/share/3UM8Hxg

This was originally reported on Zulip here: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Reference.20to.20contained.20value.20set

### Additional contract requirements

Only references to contained resources are rewritten to fragment references. Values in fields that are not references remain unchanged, even when they resemble a contained resource reference.
