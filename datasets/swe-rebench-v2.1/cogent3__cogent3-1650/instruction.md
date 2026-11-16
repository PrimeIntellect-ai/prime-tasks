AnnotationDb's should support subsetting
If we have annotated features from entire genomes, then selecting a slice of some sequences will be more performant if we create a new AnnotationDb with only the subset of features that map to the selected sequences.

The `subset()` method should be added to the `SupportsQueryFeatures` protocol with the API matching `get_records_matching()`.  The implementations should return a new instance of the same db class, so separate implementations for Basic, Gff and Genbank.

This will support development of EnsemblLite
