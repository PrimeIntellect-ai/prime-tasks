SUSHI should replace ElementDefinition.type.aggregation array when modified in FSH
Some ElementDefinition array properties are additive (you should only add to them) while others should be fully replaced when edited (and perhaps there are other options too). I asked for more information on this when I filed [FHIR-31405](https://jira.hl7.org/browse/FHIR-31405) back in 2021.

The `ElementDefinition.type.aggregation` array is an array property that should be replaced in the snapshot by whatever is in the differential. To support this, however, SUSHI needs to perform special handling of how it generates the differential. More background can be seen in [this Zulip conversation](https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/restricting.20aggregation.20type/near/413120070).

Note that we will need to support things like this at a broader level, so any solution in FSH/SUSHI should be easy to apply to other element properties as well.
