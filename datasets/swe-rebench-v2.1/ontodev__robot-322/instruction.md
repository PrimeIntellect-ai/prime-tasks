unusual behavior with relax/reduce when superclass is inferred by domain
Ontology:

```
Prefix: : <http://x.org/>
Ontology: <http://x.org/>

ObjectProperty: supplies Domain: artery

Class: brain_artery
    EquivalentTo: artery and supplies some brain
    SubClassOf: artery
    SubClassOf: supplies some brain

Class: artery
Class: brain
```

The goal of the reduce command is to produce a subClassOf graph that is (1) complete and (2) non-redundant

in the above, we want to retain BA SubClassOf A

```
$ robot reduce  -i test-asserted2.omn  -o test2.ofn && (grep 'SubClassOf(:brain_artery :artery)' test2.ofn && echo YES || echo NO)
NO
```

The problem here is the interpretation of NR. The SubClassOf axiom is formally redundant if the Domain axiom is present. But we want robot to make an ontology that can be handed to simple tools that consume SubClassOf graphs and do not speak OWL or use reasoning
