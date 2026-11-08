Derive current version from git tags.
### Discussed in https://github.com/callowayproject/bump-my-version/discussions/211

<div type='discussions-op-text'>

<sup>Originally posted by **jpavlav** July 12, 2024</sup>
Hello!

First off, just want to say, thanks for forking the project and keeping it going. I've used the previous incarnations and 👍. Previously, I've used this tool only for `python` projects. Right now, I'm trying to use this tool to create a github action that is somewhat generic for bumping versions.

I thought this would be a cinch, since there is support for detecting the version from a git tag. It would prevent us from having our users include a configuration file in their repo with the version in it. However, I find that it, in the absence of the `current_version` in a config file, the tool bottoms out despite being able to detect the tagged version. Am I just missing some option here? Or is this intentional?

Examples:

```sh
bump-my-version bump --current-version 0.4.0 --dry-run minor
KeyError: "Key 'current_version' not found at 'tool.bumpversion'"
```

Does `current_version` really need to be present in the config file if the user is specifying the version? Further, does it really need to be present if there is a tagged version available? I see that it detects that:

```sh
bump-my-version bump --current-version 1.0.0 --dry-run
  Specified version (1.0.0) does not match last tagged version (0.4.0)
```

I just wanted to ask about this before I raised an issue. I'd be unopposed to making a contribution to make this possible, but I want to make sure that I'm not stepping outside of the bounds of what is intended. Thanks!</div>
