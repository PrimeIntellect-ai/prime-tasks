SUSHI should not log errors when it finds non-XML/JSON files in resource folders
See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/sushi.20beta.20error

### Additional contract requirements

- When one non-XML/JSON file is found in an input/* resource folder, log an info message containing: `Found 1 file in an input/* resource folder that was neither XML nor JSON`.
- When this notice is emitted, it must be the last info message logged during custom resource loading.
