Make plural macros (e.g. @variables) return collections of the defined objects
When working on a large model it is extremely useful to be able to manipulate large groups of variables or constraints.

To avoid repeating long lists of variable names or equations, it would be very useful if the the ‘plural macros’ (e.g. @variables and @constraints), returned collections of the newly defined objects.

For example I would like for

```
vars = @variables model begin
  x
  y[1:2]
end
```

to be equivalent to writing

```
@variables model begin
  x
  y[1:2]
end
vars = [x, y]
```
and

```
eqs = @NLconstraints model begin
  E_x, x == 1
  E_y[i ∈ 1:2], y[i] == x
end
```
should be equivalent to writing

```
@NLconstraints model begin
  E_x, x == 1
  E_y[i ∈ 1:2], y[i] == x
end
eqs = [E_x, E_y]
```

Note that this is not just a matter of laziness, but that repeating long lists of items is prone to hard-to-debug errors. I.e. spotting which item is missing in a large collection of variables or constraints can take a long time.

### Additional contract requirements

Every plural declaration macro returns a collection containing the objects it defines, in the order in which their definitions appear in the block.
