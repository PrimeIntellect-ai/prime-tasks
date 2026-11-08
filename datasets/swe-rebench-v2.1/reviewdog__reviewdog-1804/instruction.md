[github-pr-review] Mark outdated review comments as obsolete or delete such comments
With github-pr-review, if a reported line is changed to fix the reported problem, GitHub marks the comment as outdated. However, if the fix doesn't change the reported line, the previously reported comment still remains as is.

github-pr-review reporter fetches reported comments first to prevent posting the same comments, so it should be possible to detect which comments are fixed by comparing the new reported results.

It should be better to resolve fixed reported results (or mark them as obsolete or delete such comments?).

IMPACT: This problem can happen  for type check based on comment. e.g. phpstan, jsdoc type check of Typescript.

Just for reference  (in Japanese though): https://twitter.com/about_hiroppy/status/1258699418796097537

### Additional contract requirements

When a previously reported finding is no longer present in a new report, handle its existing GitHub pull-request review comment as stale by resolving it, marking it obsolete, or deleting it. Apply this handling only to comments belonging to this reporter; comments belonging to other reporting tools must remain untouched.
