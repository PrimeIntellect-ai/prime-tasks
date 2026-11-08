No easy way to put a caret rule on the root element
Sometimes authors might want to assign a `short` description on the root element.  Usually our syntax for setting a short on an element is:
```
* path ^short = "My short description"
```
For the root element, there is no path -- but if we leave it blank, it's interpreted as being on the SD itself (not the root element).

This *might* work if you do:
```
* ^snapshot.element.short = "My short description"
```
but honestly, I'm not sure due to the way we do elements in the `StructureDefinition` class.

At a minimum, we should ensure the workaround works, but ideally we should define a syntax to access the root element.

### Additional contract requirements

- In a caret rule, a path of `.` targets the root element of the structure definition. This is distinct from an empty path, which targets the structure definition itself.
