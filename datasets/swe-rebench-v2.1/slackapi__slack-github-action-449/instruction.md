Templated payload variables are replaced before the payload is parsed
```
runs:
  using: "composite"
  steps:
    - name: Post a message in a channel
      uses: slackapi/slack-github-action@v2.0.0
      with:
        webhook: "${{ env.SLACK_WEBHOOK_URL }}"
        webhook-type: incoming-webhook
        # See: https://api.slack.com/reference/messaging/attachments
        payload: |
          attachments:
            - color: "${{ inputs.status == 'success' && 'good' || inputs.status == 'failure' && 'danger' || '#808080' }}"
              pretext: "${{ inputs.text }}"
              title: "Build Status: ${{ inputs.status }}"
              title_link: "${{ github.event.pull_request.html_url || github.event.head_commit.url }}"
              fields:
                - title: "Author"
                  value: "${{ github.event.head_commit.author.name }}"
                  short: true
                - title: "Repository"
                  value: "<${{ github.event.repository.html_url }}|${{ github.event.repository.full_name }}>"
                  short: true
                - title: "Head commit"
                  value: "<${{ github.event.head_commit.url }}|${{ github.event.head_commit.message }}>"
                  short: false
```

With the above call to `slack-github-action` I ran into a parsing issue. For certain commit messages, the followed error occured.

```
file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/content.js:93
      throw new SlackError(
^
SlackError: Invalid input! Failed to parse contents of the provided payload
    at Content.getContentPayload (file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/content.js:93:1)
    at Content.get (file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/content.js:28:1)
    at new Config (file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/config.js:115:1)
    at send (file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/send.js:13:1)
    at file:///home/runner/_work/_actions/slackapi/slack-github-action/v2.0.0/src/index.js:9:1
    at ModuleJob.run (node:internal/modules/esm/module_job:263:25)
    at ModuleLoader.import (node:internal/modules/esm/loader:540:24)
    at asyncRunEntryPointWithESMLoader (node:internal/modules/run_main:117:5)
```

After trying a bunch of commit messages, I could simplify the string that would cause the above error to the following

`\n---\n`

This string would be inserted into `${{ github.event.head_commit.message }}>`

This is a YAML-directive. Which is weird, because the variables do not exist at YAML-level.

**Code**

I then further tracked it down to the following code.

First, it translates the variables to their values. Here

https://github.com/slackapi/slack-github-action/blob/d07fadf6b91dd644931ee3b68600be76f0c6917c/src/content.js#L121

And

https://github.com/slackapi/slack-github-action/blob/d07fadf6b91dd644931ee3b68600be76f0c6917c/src/content.js#L155-L166

It tries to parse the payload parameter as YAML

https://github.com/slackapi/slack-github-action/blob/d07fadf6b91dd644931ee3b68600be76f0c6917c/src/content.js#L64-L77

If that fails, it tries to parse the payload parameter as JSON

https://github.com/slackapi/slack-github-action/blob/d07fadf6b91dd644931ee3b68600be76f0c6917c/src/content.js#L78-L100

If that fails, it exits.

**What I think is the problem**

[HIDDEN]

[HIDDEN]

This might also have security implications, since the inserted variables could modify the yaml document. I know to little about YAML and use cases for `slack-github-action` to be sure.

### Additional contract requirements

- Template-variable values must be treated as payload data, not as YAML or JSON syntax. They must not alter the payload's structure.
- When templating is enabled, variables in payload content must continue to resolve to their values.
