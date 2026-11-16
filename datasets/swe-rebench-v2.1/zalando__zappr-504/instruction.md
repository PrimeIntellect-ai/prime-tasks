Labels bug without config
When there is no config for the labels check, Zappr does nothing, which causes PRs to hang in "waiting for status" state. It should instead mark the commit as green.

Relevant line: https://github.com/zalando/zappr/blob/master/server/checks/PullRequestLabels.js#L54
