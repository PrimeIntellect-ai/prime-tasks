SUSHI fails to find element slices when other elements have the same slice name
_This issue is based on my findings while investigation a bug reported on Zulip [here](https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Bug.3A.20No.20element.20found.20at.20path)._

If the same slice name is used on multiple elements, and some of these elements have paths that are sub-paths of others, SUSHI may fail to find some slice elements.  For example, given elements w/ these ids:
```
Observation.category:Foo
Observation.category:Foo.coding:Bar
Observation.category:Bar
```
if you have a rule like this in SUSHI:
```
* category[Bar] MS
```
then SUSHI will fail to find the element, reporting an error like:
> No element found at path category[Bar] for FlagRule in ObsProfile, skipping rule errors.

[HIDDEN]

### Additional contract requirements

- When elements at different path depths share a slice name, a lookup using a requested path must resolve the element at that full path rather than fail because another element at a different path has the same slice name.
