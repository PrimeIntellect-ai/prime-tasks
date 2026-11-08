`configWithAndroidVariants`must check ruleset config for current android setting
This follows up on an issue identified in the #6767 PR (see [this comment](https://github.com/detekt/detekt/pull/6767#discussion_r1444075312)).

### Context
Some rules in the formatting ruleset (aka. ktlint wrapper) use different default values if the code is part of an android project. The user may configure this setting at the ruleset level.

```yaml
formatting:
  active: true
  android: true
```

Prior to #6767 a `Rule` was always instantiated with the rule**set** config and the default function of the `ConfigAware` interface allowed access to the rule config.

### The change
This PR would change the delegated `configWithAndroidVariants` property [HIDDEN] This makes the solution very brittle and dangerous to use in different contexts. Therefor there is another followup task (#6833) to clean this up.

### Additional contract requirements

- When a rule uses `configWithAndroidVariants`, its applicable defaults must reflect the Android setting configured at the ruleset level.
