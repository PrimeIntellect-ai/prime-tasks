Operation ActionType.SET_SPLIT_AMOUNT not supported
### Description

I've a rule that given a certain payee, it creates a split transaction of 50% each.
it seems that the code here is not supporting it.
is there a way to support this or a hint on how i can create a pr?

### Additional contract requirements

- A rule whose condition matches a given payee must be able to split the matching transaction into two equal 50% shares, using two `SET_SPLIT_AMOUNT` actions (one per share, `splitIndex` 1 and 2). Each action uses the split options format described in the `Action` docstring, i.e. `{"method": "fixed-percent", "splitIndex": N}` with the percentage as the action value (50).
- The two resulting child transactions must have equal amounts and together must equal the original transaction amount.
