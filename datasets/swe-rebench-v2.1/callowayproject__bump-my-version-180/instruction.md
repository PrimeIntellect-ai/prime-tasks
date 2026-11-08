Zero-padded version parts are not working
              It seems that this fix was removed with some refactoring happened in #112. Tried with version 0.20.1 and the following config parameters:
```
current_version = "5.06.0"
parse = "(?P<major>\\d+)\\.(?P<minor>\\d+)\\.(?P<patch>\\d+)"
serialize = ["{major}.{minor:02}.{patch}"]
search = "{current_version}"
replace = "{new_version}"
```
Increasing minor would result in version 5.70.0 which is obviously wrong. Any chances we get this functionality back? Or is there any other possibility to have fixed length version numbers?

_Originally posted by @reindlt in https://github.com/callowayproject/bump-my-version/issues/26#issuecomment-2071756686_

### Additional contract requirements

- When parsed with `(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)`, `5.06.0` must produce `{"major": "5", "minor": "06", "patch": "0"}`.
