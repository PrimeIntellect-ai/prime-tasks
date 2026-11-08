GHEvent is missing new events that is breaking Jenkins plugin usage
**Describe the bug**
Getting error:
```
com.fasterxml.jackson.databind.exc.InvalidFormatException: Cannot deserialize value of type `org.kohsuke.github.GHEvent` from String "merge_queue_entry": not one of the values accepted for Enum class: [GOLLUM, ALL, INTEGRATION_INSTALLATION_REPOSITORIES, META, DOWNLOAD, FORK_APPLY, CHECK_RUN, MARKETPLACE_PURCHASE, PROJECT_CARD, PUSH, PAGE_BUILD, TEAM_ADD, REPOSITORY_VULNERABILITY_ALERT, PACKAGE, DELETE, DEPLOYMENT_STATUS, WATCH, FOLLOW, ORG_BLOCK, ORGANIZATION, COMMIT_COMMENT, ISSUE_COMMENT, REPOSITORY_IMPORT, GITHUB_APP_AUTHORIZATION, CODE_SCANNING_ALERT, CHECK_SUITE, FORK, GIST, CONTENT_REFERENCE, REPOSITORY, INSTALLATION_REPOSITORIES, REPOSITORY_DISPATCH, MILESTONE, STAR, LABEL, MEMBERSHIP, SECURITY_ADVISORY, PROJECT_COLUMN, TEAM, PULL_REQUEST_REVIEW, RELEASE, PUBLIC, WORKFLOW_RUN, STATUS, PULL_REQUEST, PROJECT, WORKFLOW_DISPATCH, CREATE, MEMBER, REGISTRY_PACKAGE, INSTALLATION, DEPLOYMENT, PULL_REQUEST_REVIEW_COMMENT, DEPLOY_KEY, PING, ISSUES]
 at [Source: (String)"[{"id":......
```

When trying to connect to github app from jenkins.

**To Reproduce**
1. Set up Jenkins Github App
2. No event subscriptions are needed as this occurs even when nothing is selected
3. Start creating a new Github App Credential in jenkins
4. Once all the fields are set hit `Test` to test the connection
5. It should fail with the above error

**Expected behavior**
Jenkins Github App Connectivity should work with new events

**Desktop (please complete the following information):**
 - OS: iOS
 - Browser chrome
 - Version latest

**Additional context**
Create this PR with possible fix and more info https://github.com/hub4j/github-api/pull/1233

Creating this issue as I was unsure if the PR was enough and also for visibility

### Additional contract requirements

- The `merge_queue_entry` event must be represented by `GHEvent.MERGE_QUEUE_ENTRY` and be deserializable from GitHub App event data.
