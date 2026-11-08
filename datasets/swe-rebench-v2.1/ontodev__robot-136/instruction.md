Relax operation is currently incomplete
See also #7

Currently relax only inspects and materializes SomeValuesFrom. This is problematic in the following scenario:

Given:

```
'craniofacial suture' EquivalentTo 'fibrous joint' and connects exactly 2 'head bone'
```

with no other logical axioms for craniofacial suture. Assume also that Elk is used.

The axiom will be invisible to Elk, to `reason` will produce no superclasses.

Currently, when we pass this to `relax` it produces nothing, because the QCR pattern is not handled. Also we do not relax named superclasses.

Possible candidates for relax to produce.

 1. SubClassOf 'fibrous joint'
 2. SubClassOf connects some 'head bone'
 3. SubClassOf connects exactly 2 'head bone'

These are *not* guaranteed complete. To get complete inferences a DL reasoner must be used. However, we assume this is not possible here so we use relaxation to produce useful if incomplete final axioms, either directly, or as input for EL reasoning.

All of these are valid. 1 and 2 are required for producing a complete basic existential graph.
