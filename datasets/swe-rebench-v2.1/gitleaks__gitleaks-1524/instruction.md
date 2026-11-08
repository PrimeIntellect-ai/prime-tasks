Fix config extend validation + allowlist
> We use a toml file in our repo to _extend_ the default configuration, like mentioned in the PR I believe to cause this issue: https://github.com/gitleaks/gitleaks/pull/1463
>
> As an example, our "local" config looks like this:
>
> ```
> [extend]
> # useDefault will extend the base configuration with the default gitleaks config:
> # https://github.com/zricethezav/gitleaks/blob/master/config/gitleaks.toml
> useDefault = true
>
> # An array of tables that contain information that define instructions
> # on how to detect secrets
> [[rules]]
> id = "generic-api-key"
> [rules.allowlist]
> 	description = "False positive. Keys used for colors match the rule, and should be excluded."
> 	files = ['''Some_Files\.xaml''']
> ```
>
> In this case, the `generic-api-key` rule incorrectly flagged some of our hex-defined colors in a XAML file. Since the update, we now get this error:
>
> `FTL Failed to load config error="generic-api-key: both |regex| and |path| are empty, this rule will have no effect"`
>
> But... the `[id]` isn't empty?
>

_Originally posted by @celloza in https://github.com/gitleaks/gitleaks/issues/1507#issuecomment-2352550208_

While researching this, I also noticed that [rule allowlists don't get merged with extend](https://github.com/gitleaks/gitleaks/blob/97dbe1ef0969f6162e061a5418063f19ed729497/config/config.go#L237).

### Additional contract requirements

- When a configuration extends another configuration and both define a rule with the same ID, the extending entry may omit that rule's detection regex and path. In that case they are taken from the inherited rule, and the merged rule is validated as a whole, so a valid inherited rule is accepted.
- Allowlist entries (commits, paths, regexes and stop words) that the inherited and the extending entries define for the same rule all apply. Entries from either side are kept; neither side's entries replace the other's.
- A rule that has neither a detection regex nor a path after merging is rejected with an error.
