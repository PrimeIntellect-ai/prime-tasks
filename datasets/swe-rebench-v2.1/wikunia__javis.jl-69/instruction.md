Bug: can't use id if frames are not defined
We messed something up by a bit as we allow not defining the frames when one wants to use the same frames as the action before.
As both `frames` and `id` are Symbols it is not possible to write

```
Action(1:100, ground)
Action(:id, (args...)-> 1)
```

one needs to write
```
Action(1:100, ground)
Action(:same, :id, (args...)-> 1)
```

which is a bit odd and the error message is also not extremely nice. [HIDDEN] If that is the case like in

```
Action(1:100, ground)
Action(:typo, :id, (args...)-> 1)
```
we throw an error.

In this case:

```
Action(1:100, ground)
Action(:id, (args...)-> 1)
```

we interpret it as:
```
Action(1:100, ground)
Action(:same, :id, (args...)-> 1)
```

### Additional contract requirements

- `Action(:id, func, args...)` uses `:id` as the action ID and inherits the frames from the preceding action, equivalent in behavior to `Action(:same, :id, func, args...)`.
- A call such as `Action(:typo, :id, func, args...)` must fail with an error when `:typo` is supplied as a frame symbol instead of `:same`.
