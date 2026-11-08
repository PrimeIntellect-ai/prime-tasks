Remove Nexus metadata from payloads during the import
**Motivation**
Some resource still contain Nexus metadata in their original payloads before fields starting with `_` were forbidden.
The import tool can take care of cleaning up those fields

**Acceptance criteria**
1. During an import, all fields starting by `_` at the root level are removed from the original payload before the resource is evaluated
