Recursion Bug for Extensions w/ Context Set to Self
Complex extensions may be recursive (e.g., contain a nested extension referring to themself). In this case, the extension should add itself to its `Context:`. If an author attempts to do this, however, SUSHI fails due to infinite recursion.

Example (on [FSH Online](https://fshschool.org/FSHOnline/#/share/401ycyI)):
```
Extension: Node
Context: Device, Node
Title: "Node"
Description: "A node in a file system"
* extension contains name 1..1 and isFolder 1..1 and Node named children 0..*
* extension[name].value[x] only string
* extension[isFolder].value[x] only boolean
```
