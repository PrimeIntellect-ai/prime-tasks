Support copying specific files via copy-extras
<!--- Provide a general summary of the issue in the Title above -->

## Expected Behaviour
<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->

```sh
faas-cli build  --copy-extra=./models/Prices-RF-v1.0.0.pkl
```

should copy the file `./models/Prices-RF-v1.0.0.pkl` to `build/models/Prices-RF-v1.0.0.pkl`

## Current Behaviour
<!--- If describing a bug, tell us what happens instead of the expected behaviour -->
<!--- If suggesting a change/improvement, explain the difference from current behaviour -->
```sh
faas-cli build  --copy-extra=./models/Prices-RF-v1.0.0.pkl
```
produces an error

```
Errors received during build:
- error creating dest file: open build/foo/models/Prices-RF-v1.0.0.pkl: no such file or directory
```

## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug with details on how you -->
<!--- arrived at your diagnosis, or ideas how to implement the addition or change -->
[HIDDEN]


## Context
<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us come up with a solution that is most useful in the real world -->

This was reported on Slack

> Also, related to the one above, I was wondering whether it is expected behaviour that I can only seem to copy files or folder in the root folder, but not subfolders. For example: `faas-cli build --filter vis-explainmodel --copy-extra=./models works` as expected, but running `faas-cli build --filter vis-explainmodel --copy-extra=./models/HousePrices-RF-v1.0.0.pkl `does not:
> Errors received during build:
> ```
> - error creating dest file: open build/vis-explainmodel/function/models/HousePrices-RF-v1.0.0.pkl: no such file or directory
> ```
> I could open an issue for this if this is unexpected behaviour.

## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* FaaS-CLI version ( Full output from: `faas-cli version` ): 0.12.13

### Additional contract requirements

- For a named function, the build output is function-specific: `faas-cli build --copy-extra=./models/Prices-RF-v1.0.0.pkl` places the file at `build/<function-name>/models/Prices-RF-v1.0.0.pkl`, preserving the source-relative directory structure. The `build/models/...` destination described above is relative to the function's build context, not directly under the top-level `build` directory.
- Missing intermediate directories in the destination are created automatically before a file is written.
