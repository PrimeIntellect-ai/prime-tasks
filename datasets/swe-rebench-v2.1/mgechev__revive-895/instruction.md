Linter rule to check the consistency of make(map[type]type) vs empty map[type]type{}
**Is your feature request related to a problem? Please describe.**
There are two ways of declaring a map: either via `make` or via literal. Some projects might want to require to be consistent by choosing this or that way of map declaration.

**Describe the solution you'd like**
I'd like to let the user choose between the styles (either `make` or via literal). `make(map[type]type, size)` will always be allowed, as well as `map[type]type{k1: v1, k2: v2}`. I'm also considering an option to check or ignore map descendant types (e.g. `type Map map[string]string`), on by default.

**Describe alternatives you've considered**
I didn't find any solution.

**Additional context**
IMO, consistent code, be it opinionated or not, is better than inconsistent. Also, I'm in favor for `make(map[type]type)` because it's then consistent with `make(map[type]type, size)`. Also, when a descendant type is declared and then used, it's not clear for the reader if it's a struct or a map, when we call it as `Map{}`.

P.S. I can implement such a linter rule, if it makes sense to the others.

### Additional contract requirements

Expose the map-style rule through revive's user-configurable rule configuration under the identifier `enforce-map-style`. The selected style applies by default to named types whose underlying type is a map, including types declared from another named map type.
