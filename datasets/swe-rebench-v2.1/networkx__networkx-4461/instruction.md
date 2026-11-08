Allow binomial_tree() to create directed graphs (via create_using parameter)
`binomial_tree() ` doesn't seem to allow the `create_using` parameter to get passed and as a result, one can't create a directed binomial graph.

This seem like a inadvertent omission and easy to fix. I will put in a PR to address this soon.
