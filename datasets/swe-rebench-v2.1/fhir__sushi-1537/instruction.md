SUSHI should warn when multiple value[x] choices are used
SUSHI should log a warning if multiple value[x] choice elements are applied to an Instance. For example, both `valueString` and `valueCodeableConcept` cannot both be assigned on an Observation instance. In this case, the FHIR validator reports an error, but SUSHI does not.

Example FSH: https://fshschool.org/FSHOnline/#/share/3pKpG5X
Zulip thread: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Multiple.20Observation.20values

### Additional contract requirements

- SUSHI reports a conflict on an Instance as an error. It may additionally log a warning.
- Different indexed occurrences of a repeating element are distinct; assigning different choice types at different indices does not constitute a conflict.
