Standardise markup for URLs in docs
### Describe the feature or problem you’d like to solve

> Something I realized over the course of this PR is that URLs formatted with `<` and `>` are the only variants that get turned into links on the CLI manual website.
>
> Rather than extending this PR further, that might be a great follow up to review that behavior and align it.
>
> _Originally posted by @andyfeller in https://github.com/cli/cli/pull/8342#discussion_r1412121749_

### Proposed solution

Another round of checking current manual webpages or markers in code base one by one.

### Additional context

From my memory of proposing #8342, the most un-marked case is `github.com`, which is usually used to denote the `HOST`.

https://github.com/cli/cli/blob/b215d03e7b5990ea35bc0870a55d7b84f5d8c987/pkg/cmd/extension/command.go#L303-L304
https://github.com/cli/cli/blob/b215d03e7b5990ea35bc0870a55d7b84f5d8c987/pkg/cmd/search/code/code.go#L42-L44
https://github.com/cli/cli/blob/b215d03e7b5990ea35bc0870a55d7b84f5d8c987/pkg/cmd/root/help_topic.go#L45-L47
