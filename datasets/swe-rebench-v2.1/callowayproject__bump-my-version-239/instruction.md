bump-my-version does not fail if script hooks fail
* bump-my-version version: 0.26.1
* Python version: 3.12.3
* Operating System: Ubuntu 22.04

### Description

When a command in a pre or post commit hook fails, I expect the bump to fail as well, but this does not happen.

This is because the errors on `subprocess.run` calls are not handled, but simply logged and ignored. See the `0.26.1` tag version of the `run_hooks()` function:
https://github.com/callowayproject/bump-my-version/blob/683904a587a37305e42a29af9c53f27c8f369550/bumpversion/hooks.py#L92-L106

### What I Did

Running bump-my-version with the following config:
```toml
[tool.bumpversion]
current_version = "0.1.3"
parse = "(?P<major>\\d+)\\.(?P<minor>\\d+)\\.(?P<patch>\\d+)"
serialize = ["{major}.{minor}.{patch}"]
search = "{current_version}"
replace = "{new_version}"
regex = false
ignore_missing_version = false
ignore_missing_files = false
tag = false
sign_tags = false
tag_name = "v{new_version}"
tag_message = "Bump version: {current_version} → {new_version}"
allow_dirty = false
commit = true
message = "Bump version: {current_version} → {new_version}"
commit_args = ""
pre_commit_hooks = ["exit 1"]
post_commit_hooks = ["exit 2"]
```

---

Is there any chance that this feature would be implemented?
Thank you
