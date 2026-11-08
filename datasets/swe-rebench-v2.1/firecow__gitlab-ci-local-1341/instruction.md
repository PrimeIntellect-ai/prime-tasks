`.gitlab-ci-local-variables.yml` not being correctly parsed.
I can't seem to get `.gitlab-ci-local-variables.yml` to be read in as variables.

I'm trying to understand how to set this up, and when running on my `.gitlab-ci.yml` file, `gitlab-ci-local` fails to run because a custom variable our yaml isn't configured.

Which is fine, as I can configure it myself.

If I go to do so through the CLI using `gitlab-ci-local --list --variable CUSTOM_VAR=value` it works fine.

Same goes for setting it up using `.gitlab-ci-local-env`

However when I configure `.gitlab-ci-local-variables.yml` as described in the readme:

```yml
---
  CUSTOM_VAR: value
```

I get an error saying that my variable isn't defined.

On debugging the code, I find that the logic for the expanded variables is the same, so I believe the values set in variablesFromFiles and expanded aren't correctly parsed by the rest of the code (since variables seem like they can be read in from multiple places, not just the unified expanded).

Or, am I misunderstanding how to use this tool?

If so, could more guidance be added to the readme please?

For now, I can use `--variable` but this won't scale for a more thorough solution :/

### Additional contract requirements

- Variables declared in `.gitlab-ci-local-variables.yml` must be loaded and made available to CI jobs, so a configured variable such as `CUSTOM_VAR` is not treated as undefined.
