Add support for SPARQL UPDATE queries with multiple clauses
Currently, only single clauses are supported. We instead also want things like:

```
DELETE DATA {<https://css.verborgh.org/home/lights#3> <urn:tmp:philips:hue#hue> "1338"^^<http://www.w3.org/2001/XMLSchema#integer>.};
INSERT DATA {<https://css.verborgh.org/home/lights#3> <urn:tmp:philips:hue#hue> "1337"^^<http://www.w3.org/2001/XMLSchema#integer>.}
```
