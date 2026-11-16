Type inference broken when there are comments between arguments on type definition
<!--- Provide a general summary of the issue in the Title above -->
I'm not 100% sure this issue belongs here (vs. `elm-language-client-vscode`) but I think it does. Let me know if I should move it there.

SSCCE:
```elm
type MyType
    = MyType
        -- First comment
        -- Second comment
        -- Third comment
        Int


someFunction : MyType -> Bool
someFunction mytype =
    case mytype of
        MyType _ ->
            True
```
<img width="472" alt="image" src="https://user-images.githubusercontent.com/4342234/232826772-f9594f5e-0aeb-4f3d-b22c-fd7f1f34339d.png">


## Expected Behavior
No errors.
<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->

## Current Behavior
The following error treats the variant `MyType` as taking *4* arguments when it actually takes only one (and has 3 comments):
```
This `case` does not have branches for all possibilities.
Missing possibilities include:
  MyType _ _ _ _
```
<!--- If describing a bug, tell us what happens instead of the expected behavior -->
<!--- If suggesting a change/improvement, explain the difference from current behavior -->

## Possible Solution
Once the comments are deleted or moved up the error disappears. It seems that comments are tokenized and somewhere interpreted as type arguments.

The weirdest thing though is that if I check the VSCode plugin box `Only Update Diagnostics On Save
` this error disappears.

I've also seen the error disappear when I save the file but sometimes it does not.
<!--- Not obligatory, but suggest a fix/reason for the bug, -->
<!--- or ideas how to implement the addition or change -->

## Steps to Reproduce (for bugs)
<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->
1. Copy the code to an Elm file;
2. Edit the file and see the error.

<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us come up with a solution that is most useful in the real world -->

## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* Version used: 2.6.0
* Editor used: VSCode
* Environment name and version (e.g. node.js 5.4): Node 19.8.1
* Operating System and version: MacOS 13.2.1
