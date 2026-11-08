Apply mutally exclusive Age labels
Hi there, great work on this Action. I am wondering if it's possible to apply different labels based on age. Right now I have a config which looks a bit like this:

```yaml
  - label: "Age: Getting Stale"
    age: 8d

  - label: "Age: Quite Stale"
    age: 22d
```

The problem I am having with this is that it will apply _both_ labels after 22 days, whereas I would ideally like it to simply apply one or the other based on the age of the pull request (or issue, but in my case for PRs). Something like this I guess (similar to the upper/lower limits for file changes).

```yaml
  # Pseudo-code, don't actually use this!
  - label: "Age: Getting Stale"
    age:
      - older_than: 8d
      - newer_than: 22d

  # Pseudo-code, don't actually use this!
  - label: "Age: Quite Stale"
    age:
      - older_than: 22d
```

Is there a way to configure this already (maybe with a `negate` rule?), or is this something we would need to add? I know about the [last modified matcher](https://github.com/srvaroa/labeler?tab=readme-ov-file#last-modified), but the goal is to label PRs which were originally opened a long time ago (doesn't matter if they have been touched recently).

If this is a new feature, please let me know where I can get started implementing this.

### Additional contract requirements

Age-based criteria must support a lower bound, upper bound, or both, so a label can be restricted to a distinct age band. In YAML, age bounds are provided under `age-range` using optional `at-least` and `at-most` duration values. Age is measured from the PR or issue creation time, regardless of subsequent updates.
