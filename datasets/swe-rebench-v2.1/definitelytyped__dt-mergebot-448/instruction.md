Fails to comment on huge PRs
TL;DR: when opening huge PRs, such as https://github.com/DefinitelyTyped/DefinitelyTyped/pull/62106 - mergebot never picks it up.

> Someone would need to [log into the azure functions](https://github.com/DefinitelyTyped/dt-mergebot/#meta ) to read the logs to know exactly why, but there is a 'too big to review' style check in the bot which this doesn't seem to be getting hit with.
> _Originally posted by @orta in https://github.com/DefinitelyTyped/DefinitelyTyped/issues/62106#issuecomment-1242663828_

Other huge PRs that it didn't pick up:
- https://github.com/DefinitelyTyped/DefinitelyTyped/pull/61722
- https://github.com/DefinitelyTyped/DefinitelyTyped/pull/62194
- https://github.com/DefinitelyTyped/DefinitelyTyped/pull/62193
- https://github.com/DefinitelyTyped/DefinitelyTyped/pull/62192

### Additional contract requirements

- For PRs with too many files, mergebot must apply the GitHub label `Too Many Files` (label ID `LA_kwDOAFz6BM8AAAABEGgY4Q`).
