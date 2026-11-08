Macros formatted incorrectly due to added white space
Hi, I noticed that some macros are formatted incorrectly by the formatter.  For example, I have the following two macro calls
```julia
@NamedTuple{a::Int, b::Int}[]

@SVector[@SVector[1, 2], @SVector[1, 2]]
```
which got formatted incorrectly into
```julia
@NamedTuple {a::Int, b::Int}[]

@SVector [@SVector [1, 2], @SVector [1, 2]]
```

It looks like the formatter currently does not handle these special macro call syntax properly, and this has caused it to break my existing code. Is there any plan to fix this? Thanks! (I'm using the "blue" code style)

### Additional contract requirements

- When given the following already-spaced input, the formatter must preserve it exactly, including the spaces after `@NamedTuple` and the inner `@SVector`:
```julia
@NamedTuple {a::Int, b::Int}[]

@SVector[@SVector [1, 2]]
```
