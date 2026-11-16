DatamodelConverter is missing support for some entity types
This should also have `MediaInfoIdValue` and others (lexeme, form, sense):
https://github.com/Wikidata/Wikidata-Toolkit/blob/6754af679e90480cae596b733f28d2062cc04ebf/wdtk-datamodel/src/main/java/org/wikidata/wdtk/datamodel/helpers/DatamodelConverter.java#L418-L427

### Additional contract requirements

The generic value-conversion path must also recognize MediaInfoIdValue, LexemeIdValue, FormIdValue, and SenseIdValue inputs, producing copies that preserve each identifier and site IRI rather than reporting an unsupported entity ID.
