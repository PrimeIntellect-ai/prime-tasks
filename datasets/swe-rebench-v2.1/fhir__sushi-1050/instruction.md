SUSHI not recognizing CodeSystem codes defined using ^concept
If an author defines codes in a CodeSystem using `^concept` like the following:
```
* ^concept[2].code = #101
* ^concept[2].display = "display 2"
* ^concept[2].definition = "definition 2"
```
then SUSHI does not recognize those codes when used in a ValueSet.  This is reproduced in FSH Online here: https://fshschool.org/FSHOnline/#/share/3vLYBUq

Although this is not the recommended way to create CodeSystems, it still should be supported.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/sushi.20suddenly.20failing.20on.20cs.2Fvs.20codes.20post.20upgrade/near/274386821
