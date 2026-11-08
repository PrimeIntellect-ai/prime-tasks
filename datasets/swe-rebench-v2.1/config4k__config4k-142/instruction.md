Respect Mutable* (List / Map / Set)
Hi,

When loading a class containing a MutableSet AND the set contains only one element is loaded as SingletonSet (which is not mutable)

(Following is not compile checked)

```
data class Bla (val test: MutableSet<String>)
```
