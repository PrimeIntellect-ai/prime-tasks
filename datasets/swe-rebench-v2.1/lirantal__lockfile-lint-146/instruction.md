Bug: CLI Argument parsing typos invokes other validates
<!--- Provide a general summary of the issue in the Title above -->

## Expected Behavior
<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->

Not to validate the integrity by default via CLI command
e.g.)
```
npx lockfile-lint --validate-https -validate-package-names --validate-integrity --path yarn.lock
```


## Current Behavior

<!--- If describing a bug, tell us what happens instead of the expected behavior -->
<!--- If suggesting a change/improvement, explain the difference from current behavior -->
```
npx lockfile-lint --validate-https -validate-package-names --validate-integrity false --path yarn.lock
```
Always seems to validate the integrity is sha512



## Possible Solution

<!--- Not obligatory, but suggest a fix/reason for the bug, -->
<!--- or ideas how to implement the addition or change -->

## Steps to Reproduce (for bugs)

<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->

1. Run `npx lockfile-lint --validate-https -validate-package-names --validate-integrity --path yarn.lock`
with a lockfile that is using sha1 integrity
<img width="659" alt="image" src="https://user-images.githubusercontent.com/1212576/193951700-6fbf701b-fb4e-4445-908c-3662089b0be7.png">

Have also tried passing false as an aargument to `--validate-integrity` which also did not work


## Context

<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us come up with a solution that is most useful in the real world -->

## Your Environment

<!--- Include as many relevant details about the environment you experienced the bug in -->

- Library Version used: 4.9.5
- Node.js version (e.g. Node.js 5.4): 16
- Operating System and version (desktop or mobile): MacOS 12.6

### Additional contract requirements

- Passing `false` to `--validate-integrity` must disable integrity validation.
