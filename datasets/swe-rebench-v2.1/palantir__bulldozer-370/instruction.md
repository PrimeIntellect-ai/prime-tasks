PRs left open when GitHub is too busy
We have been experiencing an intermittent issue where merge requests are rejected by the GitHub API:

```json
{
	"level": "info",
	"rid": "cf3n6dbn37kclfh117a0",
	"github_event_type": "status",
	"github_delivery_id": "3cb85cd2-96e7-11ed-9516-9f680ab3bc27",
	"github_installation_id": 1,
	"github_repository_owner": "acme",
	"github_repository_name": "anvils",
	"github_pr_num": 26725,
	"time": "2023-01-18T04:19:02.713727629Z",
	"message": "Merge rejected due to unsatisfied condition: \"Base branch was modified. Review and try the merge again.\""
}
```

A small percentage of PRs are left unmerged by bulldozer due to the above issue. At this point there are no more triggering events affecting the PR so it never retries. This seems to happen when we have a lot of PRs getting merged in quick succession and is sporadic in nature.

I am happy to contribute a fix for this, but I am not sure what the best approach might be:

1. Retry after a small delay? In the event bulldozer is restarted the PR would once again end up left open, but this would be exceedingly rare and so is acceptable.
2. Periodically scan PRs in a repo? This feels like a can of worms best not opened.

Or if you have any other ideas I would be grateful.

### Additional contract requirements

- The merge attempt logic is exposed in package `bulldozer` as `attemptMerge(ctx context.Context, pullCtx pull.Context, merger Merger, method MergeMethod, commitMsg CommitMessage) (merged bool, retry bool)`.
- `merged` is true only when the pull request was merged successfully, and false otherwise.
- When a merge is rejected by the GitHub API with HTTP status 405 and the message `Base branch was modified. Review and try the merge again.`, `attemptMerge` reports `retry` as true so the caller can re-attempt the merge.
- When a merge is rejected by the GitHub API with HTTP status 405 for any other message, `attemptMerge` reports `retry` as false.
