`robot template`: Drop non-robot cols?
## Overview
Docs:
> `>A` (axiom annotations): ROBOT can also annotate logical and annotation axioms. The axiom annotation will be on the axiom created on the cell to the left of the `>A*` template string. The `>` symbol can be used in front of any valid annotation character (`>A`, `>AT`, `>AL`, `>AI`)

Sometimes I have an issue where I create ROBOT templates that are also used by curators. And sometimes the most ideal layout for curation involves a non-robot column between robot cols, which sometimes causes a kind of syntax issue, resulting in a column of axioms annotations are getting ignored.

## Example case
|`exact_synonym`             |`source_id`             |`source_label`|`synonym_type`                |
|----------------------------|------------------------|--------------|------------------------------|
|`A oboInOwl:hasExactSynonym`| `>A oboInOwl:hasDbXref`|              | `>AI oboInOwl:hasSynonymType`|

Here, someone might want to see source ID and source label side-by-side, but this creates a “break” between the axiom annotation columns. So when the template is run, the `synonym_type` column doesn’t end up doing anything

## Suggestion
I’m wondering if this is intentional design, and if there's some reason for this that I'm not aware of.

But if not, then I would suggest that "non robot" columns (columns without a robot subheader) should simply be dropped during preprocessing.
