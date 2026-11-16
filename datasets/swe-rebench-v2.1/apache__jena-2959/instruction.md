"Safe" flag for riot RDFS inference
### Version

4.7.0

### Feature

Currently, riot RDFS inference outputs “generalized” RDF which may not be parsable by other tools (including various Jena CLI tools). For example:

`data.ttl`

```ttl
PREFIX ex: <http://example.org/>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

ex:louie ex:birthdate "2022-08-11”^^xsd:date .
```

`vocab.ttl`

```ttl
PREFIX ex: <http://example.org/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

ex:birthdate rdfs:range xsd:date .
```

Output of `riot --rdfs=vocab.ttl data.ttl`

```ttl
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

"2022-08-11”^^xsd:date rdf:type xsd:date .
```

… which is generalized RDF due to the literal in the subject position.

It would be nice if there were a flag to filter out such triples (using [SafeGraph](https://github.com/apache/jena/blob/main/jena-core/src/main/java/org/apache/jena/reasoner/rulesys/impl/SafeGraph.java)), so as to avoid errors when subsequently processing the output with tools that don't accept generalized RDF.

I’m interested in contributing a solution, but would need some pointers as to where in the codebase this should go.

### Are you interested in contributing a solution yourself?

Perhaps?

### Additional contract requirements

- Add a public static method `isValidAsRDF(Node s, Node p, Node o)` in `org.apache.jena.sparql.util.NodeUtils` that returns `true` exactly when the three nodes form a valid RDF triple: the subject is a URI or blank node, the predicate is a URI, and the object is a URI, blank node, literal or node-triple. It returns `false` for any other node kind, including variables and `null`.
- Add a public static method `isValidAsRDF(Node g, Node s, Node p, Node o)` in `org.apache.jena.sparql.util.NodeUtils` that returns `true` exactly when the graph node is a URI or blank node and the triple `(s, p, o)` is valid as above. It returns `false` when the graph node is `null`, a variable or a literal.
- Add a public static method `removeGeneralizedRDF(StreamRDF data)` in `org.apache.jena.rdfs.RDFSFactory` that returns a `StreamRDF` which forwards to `data` only triples that are valid RDF as defined above, dropping generalized RDF such as triples with a literal in subject position.
- The requested way to omit generalized triples is the reusable `StreamRDF` filter; a new riot command-line flag is not required.
