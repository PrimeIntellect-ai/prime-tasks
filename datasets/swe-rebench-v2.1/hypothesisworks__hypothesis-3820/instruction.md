Warn when passing *strategies* as elements to `sampled_from` (rather than to `one_of`)?
I was just making an error passing values of strategy type to the `elements` parameter of `sampled_from` when what I should've been using was `one_of`. This gave me some initially unexpected results, as I was dealing in the body of my test case with values of strategy type than rather than the values I expected to be generated from them.

What do you think about a warning message or an error when passing strategies as elements to `sampled_from`? Naively, it seems like this would more often be in error (mis/incomplete understanding of the API, confusing `sampled_from` and `one_of`) than in intention.

Regardless, thanks for a great library!

### Additional contract requirements

- If a test raises a `TypeError` whose message contains `SearchStrategy` after drawing a strategy-valued element from `sampled_from` whose collection consists entirely of strategies, attach exactly one matching exception note. The note must begin with `sample_from was given a collection of strategies` and end with `Was one_of intended?`.
