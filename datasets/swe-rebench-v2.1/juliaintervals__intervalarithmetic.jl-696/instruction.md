`isdisjoint_interval` broken for multiple arguments
We have
```julia
julia> isdisjoint_interval(interval(1, 2), interval(3, 4), interval(5, 6), interval(1, 2))
true
```
even though clearly the first and last interval are not disjoint. The documentation of the `isdisjoint_interval` function says
```
  isdisjoint_interval(x, y)

  Test whether x and y have no common elements.
```
It doesn't actually specify how multiple arguments are handled, but presumably it would return true if all of them are disjoint and false if any two of them overlap. This is how the three argument version works at least
```julia
julia> isdisjoint_interval(interval(1, 2), interval(3, 4), interval(1, 2))
false
```

The implementation
```julia
[HIDDEN]
```
basically does a reduction using the pairwise version. [HIDDEN] One could get a correct implementation by [HIDDEN] It would be possible to do this is almost linear time if one [HIDDEN], but I'm not sure one could do much better than that. I think [HIDDEN] would work fine here since one doesn't want to pass too many arguments to a Julia function either way.

### Additional contract requirements

- With multiple interval arguments, `isdisjoint_interval` must return `true` exactly when every pair has no common elements, and `false` if any pair has a common element.
