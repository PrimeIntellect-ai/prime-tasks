Invalid tag when assuming role
Hi 👋
I've just been trying to use the new [role-assuming feature](https://github.com/aws-actions/configure-aws-credentials/pull/17) in master, but I've run into an issues with the session tagging.

I'm getting the following error:
```
##[error]1 validation error detected: Value 'dependabot-preview[bot]' at 'tags.5.member.value' failed to satisfy constraint: Member must satisfy regular expression pattern: [\p{L}\p{Z}\p{N}_.:/=+\-@]*
##[error]Node run failed with exit code 1
```

My theory is that this is caused by tagging the session with the `GITHUB_ACTOR` environment variable.
In [this line](https://github.com/aws-actions/configure-aws-credentials/blob/master/index.js#L41), the session is tagged with `GITHUB_ACTOR`.

The actor of the run (and so `GITHUB_ACTOR`) was `dependabot-preview[bot]`.
It seems that `[` and `]` are not valid characters in AWS session tags, and so this is crashing the program.

Seems like the tag must be removed or the variable sanitised.
