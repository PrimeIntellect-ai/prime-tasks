Error Populating Slices on Observation.component
The CancerGeneticVariant profile needs to slice Observation.component. SUSHI seems to be OK with populating the slices in-line, but the IG Publisher crashes with this message:

```
Caused by: org.hl7.fhir.exceptions.DefinitionException: Attempt to a slice an element that does not repeat: Observation.component.code/Observation.component.code from http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab in http://hl7.org/fhir/us/mcode/StructureDefinition/CancerGeneticVariant
```

The offending lines are currently commented out so we can build the IG, but look for these lines in _CancerGenomics.fsh_:
```
* component[GeneStudied] ^short = "Gene studied [ID]"
* component[GeneStudied].code = LNC#48018-6
* component[GeneStudied].value[x] only CodeableConcept
* component[GeneStudied].valueCodeableConcept 1..1
* component[GeneStudied].valueCodeableConcept from http://www.genenames.org/geneId (extensible)
* component[VariationCode] ^short = "Discrete genetic variant"
* component[VariationCode].code = LNC#81252-9
* component[VariationCode].value[x] only CodeableConcept
etc.
```

### Additional contract requirements

The CancerGeneticVariant profile slices `Observation.component` with the following slices, declared in this order:

```
GeneStudied, VariationCode, GenomicDNAChange, GenomicSourceClass, AminoAcidChange, AminoAcidChangeType, CytogeneticLocation, CytogeneticNomenclature
```

When a profile slices a repeating element with multiple slices, the generated differential must list each slice element immediately followed by that slice's own child elements, with the slices appearing in the order they are declared. This must hold even when one slice's name is a prefix of another slice's name (for example `AminoAcidChange` and `AminoAcidChangeType`), so that no slice's children are emitted after a different slice.
