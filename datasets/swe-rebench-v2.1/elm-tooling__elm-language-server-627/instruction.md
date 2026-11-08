type inference fails with empty record pattern
<!--- Provide a general summary of the issue in the Title above -->

## Expected Behavior

The following should typecheck ok:

```elm
f : { a : Int } -> Int
f {} =
    5
```

## Current Behavior

![image](https://user-images.githubusercontent.com/16308754/113461512-d5134a00-9414-11eb-834a-e80ee65702f2.png)


## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* Version used: `elmtooling.elm-ls-vscode` `v2.1.0`
* Editor used: vscode
* Environment name and version (e.g. node.js 5.4):
* Operating System and version: linux
