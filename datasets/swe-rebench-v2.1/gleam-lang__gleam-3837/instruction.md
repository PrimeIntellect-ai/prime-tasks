Autocomplete removes/deletes code
I have the following line:
```gleam
list.drop(l, n)
```
I want to wrap it with `list.append(...)` like so:
```gleam
list.append( list.drop(l,n) )
```

So I start typing `list.` , and at some point my cursor is at the position I indicate below:
```gleam
list.list.drop(l, n)
     ^
```
now the autocomplete suggests `append` when I type `app` along with a few other functions. I want the `append` function, so I hit tab. Now my code gets turned into this:

```gleam
list.append(l, n)
           ^
```

It removed part of my code. It shouldn't have removed my code. Fortunately I can bring back my progress using ctrl+z, but this still shouldn't have happened.

### Additional contract requirements

- When selecting the `list.map` completion in the cases where the source contains `list.list.filter([1, 2, 3], todo)` or `list.mlist.filter([1, 2, 3], todo)`, the resulting expression must be `list.maplist.filter([1, 2, 3], todo)`.
