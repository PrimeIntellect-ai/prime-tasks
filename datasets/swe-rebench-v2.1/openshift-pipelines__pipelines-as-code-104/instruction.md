Pipelines gets created twice on a pull request push when it's not coming from a fork
If a user has a repo and push a branch to a repo for a PR we gets two different PipelineRun created.

Since we intercept the push (for pushing to main nightly branch etc) a pipelinerun gets created before the filtering is done to see if it match to repository.

Since we update (or syncronize) the pull_request another PR gets created.

The problem is that another pipelinerun gets created and update the status even tho it cannot find a match for it (or hopefully it shouldnt)
