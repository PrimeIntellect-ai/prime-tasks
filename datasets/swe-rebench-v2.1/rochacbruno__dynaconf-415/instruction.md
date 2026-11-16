[bug] settings.set with dotted notation limit key names that can be used
you cannot set a deeper entry with the same key as higher entry.

settings.set('a.b', 1)
settings.set('a.c', 2)
settings.set('a.c.k', 22)

--> {'c': {'k': 22}, 'b': 1}

settings.set('a.c.b', 3)

--> {'c': {'b': 3, 'k': 22}}
the higher entry 'a.b' was removed



[HIDDEN]

tries to find a quick solution, but i a don't have the time now, will bypass by using different keys :(

### Additional contract requirements

Setting a deeper dotted key must preserve existing entries outside that descendant, including a higher-level entry whose key matches a later path segment. Existing sibling descendants must also remain available.

Dotted local sets must retain Dynaconf's established mapping and list merge-marker behavior, including combining values when the corresponding merge marker requests it.
