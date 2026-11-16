Provide better error message for missing snapshot on extension
There are cases where a missing snapshot on an extension may cause a stack trace due to an uncaught exception:
```
debug TypeError: Cannot read properties of undefined (reading 'element')
    at isModifierExtension (/usr/local/lib/node_modules/fsh-sushi/dist/fhirtypes/common.js:1205:93)
    at /usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:921:69
    at Array.forEach (<anonymous>)
    at StructureDefinitionExporter.handleExtensionContainsRule (/usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:883:20)
    at StructureDefinitionExporter.setRules (/usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:674:34)
    at StructureDefinitionExporter.exportStructDef (/usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:1111:14)
    at /usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:1170:22
    at Array.forEach (<anonymous>)
    at StructureDefinitionExporter.export (/usr/local/lib/node_modules/fsh-sushi/dist/export/StructureDefinitionExporter.js:1168:30)
    at FHIRExporter.export (/usr/local/lib/node_modules/fsh-sushi/dist/export/FHIRExporter.js:27:48)
```

When using an extension definition that does not have a snapshot, the normal "missing snapshot" message should be provided.

Originally reported at https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/pre-adopt.20R5.20in.20R4.3B.20pre.20defined.20resources.3F

### Additional contract requirements

- The normal "missing snapshot" message is: `Structure Definition <url> is missing a snapshot. Snapshot is required for import.` (where `<url>` is the URL of the extension definition that is missing a snapshot).
