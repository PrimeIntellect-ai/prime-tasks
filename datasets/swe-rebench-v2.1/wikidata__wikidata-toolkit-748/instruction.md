JSON dump parsing error while running examples
I encountered below error message when running the examples `GreatestNumberProcessor` and `GenderRatioProcessor`.
```
Problematic line was: {"type":"lexeme","id":"L34069","lemmas":{"de":{"la...
Error when reading JSON for entity: Missing type id when trying to resolve subtype of [simple type, class org.wikidata.wdtk.datamodel.implementation.FormDocumentImpl]: missing type id property 'type' (for POJO property 'forms')
 at [Source: (String)"{"type":"lexeme","id":"L34070","lemmas":{"de":{"language":"de","value":"Zahnl\u00fccke"}},"lexicalCategory":"Q1084","language":"Q188","claims":{"P5185":[{"mainsnak":{"snaktype":"value","property":"P5185","datavalue":{"value":{"entity-type":"item","numeric-id":1775415,"id":"Q1775415"},"type":"wikibase-entityid"},"datatype":"wikibase-item"},"type":"statement","id":"L34070$B9D7523B-8AE6-4C39-85A2-EE7CC71C5228","rank":"normal"}],"P8376":[{"mainsnak":{"snaktype":"value","property":"P8376","datavalue""[truncated 4073 chars]; line: 1, column: 1043] (through reference chain: org.wikidata.wdtk.datamodel.implementation.LexemeDocumentImpl["forms"]->java.util.ArrayList[0])
```
The dump is automatically downloaded `20210407.json.gz`.

I tried to run the code on Windows (Build with Maven with IDEA, JDK 15.0.1) and Ubuntu (openJDK 1.8.0_282, run as IDEA remote).

It seems the dump file size is only ~200MB. Would that be correct?

Any help is appreciated. Thank you.

### Additional contract requirements

- Reading a lexeme JSON document whose `forms` value is an empty JSON object `{}` (instead of an empty array `[]`) must succeed and produce a lexeme with no forms, the same as an empty array would.
- Lexemes whose `forms` is a non-empty array must continue to deserialize with all their forms.
