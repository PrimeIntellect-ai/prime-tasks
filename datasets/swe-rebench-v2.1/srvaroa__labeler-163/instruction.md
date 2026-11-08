[feat] improve `mergeable` param or add a paramater for Has/Needs code review
The `mergeable` parameter is pretty good, however there is one limitation with it. It will pass (when `True`) if all of the checks pass, however there may be other things blocking merging (specifically it may require review). See below:


<img width="279" alt="image" src="https://github.com/user-attachments/assets/943fa38d-48b2-4a55-81cd-ee90b2639015" />

It would be good to either:

1. Update `mergeable` to account for this.
1. Add a new param for has/needs code review.


I think if we wanted to do number 1, we could maybe read [`MergeableState`](https://github.com/google/go-github/blob/3c06fc105fea5cd7216af67c1455620c8689ff1e/github/pulls.go#L46) instead so that we actually check that the PR is indeed in a clean state. I also found [this Enum](https://docs.github.com/en/graphql/reference/enums#mergestatestatus) which I don't see in the API library so not sure if we have access to that.

### Additional contract requirements

The `mergeable` parameter must be considered `True` only when the pull request is in a clean mergeable state: the GitHub `mergeable` flag is true **and** the `mergeable_state` is `clean`. A pull request that is mergeable but whose `mergeable_state` is not `clean` (for example because a review is required) must not match `mergeable: "True"`, and must match `mergeable: "False"`.
