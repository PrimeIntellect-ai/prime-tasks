Stale label not being added
Stale label not being added at all in our repo. To give a specific example, let's take https://github.com/WeblateOrg/weblate/issues/4746

On the [last nightly run](https://github.com/WeblateOrg/weblate/runs/1811488912), the log contains the following entries:

```
[#4746] Found issue: issue #4746 last updated 2021-01-06T08:51:34Z (is pr? false)
[#4746] Days before issue stale: 10
[#4746] This issue hasn't a stale label
```

So, the action sees the issue is old, gets correct stale days and sees that the label is not there. It just doesn't label it as stale.

Things most likely go wrong here:

https://github.com/actions/stale/blob/f71123a6f703377ddcfc8b5936ac224202592fc0/src/IssueProcessor.ts#L280

The question is how to figure out whether there is a bug in the action or there is something misconfigured on our side.
