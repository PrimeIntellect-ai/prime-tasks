Heuristic for comment relationships
An interesting [suggestion] from @whyrusleeping on valuing comments:

> I think that comments need a better way to be valued. Emoji responses will
> likely help here, but also I think that **increasing a comments weight if its
> author has someone respond to them later in the thread**.

[suggestion]: https://discuss.sourcecred.io/t/ipfs-cred-feedback/17/2

What if instead of increasing a comment's weight, we created new edges
according to this heuristic? If a comment mentions a user, and there were
comments by that user earlier in the thread, then the comment creates edges
pointing to those comments.

Interpreting it via edges rather than weight modification makes it harder to
use it for gaming. If we modify the weight, then a user could create a
sockpuppet account, and have the sockpuppet reference their comments, which
would increase the value of the comments out of proportion to the cred in the
sockpuppet account. Using edges ensures that the new cred flows still respect
the rest of the distribution.
