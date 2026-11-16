For-loop or range between some ints
Hi!

I wanted to range over a particular set of ints (for-loop like behavior) but I don't seem to see it supported in jet wiki.

Example:
```
{{ startInt, endInt := getNavRange(context) }}
{{ range i := startInt...endInt }}
<a href="?page={{i}}">Page {{i}}</a>
{{ end }}
```

I know there is the work around to create a slice of ints and range over it, but it's less efficient (variable allocations, unnecessary slice, ...). So I would like to know if it's supported but not documented.

### Additional contract requirements

Templates must provide the `ints(from, to)` callable to iterate over a chosen integer range without requiring the caller to construct a slice. Values yielded by the iteration must be contiguous integers beginning at `from`; the endpoint convention may be inclusive or exclusive. Iteration must not retain or materialize storage whose size grows proportionally with the number of values in the range.
