Add Support for GitHub Enterprise Instances
Hi, I wanted to use this action on an on premises GitHub Enterprise Server that has it's own url (e.g. https://git.acme.com)

I was hoping it would be possible to add a new input to the `action.yml` to support passing in a url for a Git instance that would default to GitHub.com if unfilled.

Right now it looks like the `message` field will use the instance url for it's link but the others do not.

https://github.com/8398a7/action-slack/blob/9c613f82be50ba1c5d845d3448861aba03da3d0b/src/fields.ts#L140

There might be a way to do it dynamically because this is how the `message` field gets the url for the link
https://github.com/8398a7/action-slack/blob/9c613f82be50ba1c5d845d3448861aba03da3d0b/src/fields.ts#L73-L81

### Additional contract requirements

- The action must declare a new input named `github_base_url` in `action.yml` for passing the URL of a GitHub instance.
- When `github_base_url` is unfilled (empty), the links generated for the `repo`, `commit`, `job`, `action`, and `workflow` fields must default to `https://github.com`.
- When `github_base_url` is supplied, those same fields must use the supplied URL in place of `https://github.com` as the base of their links, while preserving each field’s existing link path and label.
