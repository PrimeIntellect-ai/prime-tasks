"Now the user needs to change from_commit and to_commit if reversed_order is True" may be misleading
Hi @ishepard ,

I have noticed that during commit https://github.com/ishepard/pydriller/commit/bec86e2fe0c027032e8f66427eb4fd363c65e838 you have swap  ```from_commit``` and ```to_commit``` in the test data for the process metrics to reflect the changes you have done in commit https://github.com/ishepard/pydriller/commit/f84047a2579a4f0b282aebc66a3e6a8d13ae2871.

Although those tests pass, I think it could be misleading telling the user to reverse the order of the two parameters, for two reasons:

1. Different applications already use PyDriller, and I imagine that some of them use the ```reverse_order``` and need to change the code accordingly;

2. In the specific case of the implemented process metrics, the user does not know (and is not assumed to know) that we set up ```reverse_order = True``` in the body of the metrics. When a user calls ```commits_count('pydriller', from_commit='commit_1', to_commit='commit_10')```, he/she expects to analyse the commits in chronological order from ```commit_1``` to ```commit_10```.
The current version returns the wrong result, and the user has to call ```commits_count('pydriller', from_commit='commit_10', to_commit='commit_1')``` instead, which is IMHO a bit confusing.

Here the alternatives that I propose:

1. [HIDDEN]

2. We can leave everything as it is (but take care of point 1 in the previous list), and I can change the process metrics accordingly, [HIDDEN]

Let me know what do you think.

### Additional contract requirements

- When using `RepositoryMining` with `reversed_order=True`, callers may supply `from_commit` and `to_commit` in chronological order. The same interval must be included, traversed in reverse chronological order; callers should not need to reverse the endpoints.
- Process metrics such as `commits_count` must analyze the interval specified by the caller’s chronological `from_commit` and `to_commit` endpoints, even when their traversal is reversed.
