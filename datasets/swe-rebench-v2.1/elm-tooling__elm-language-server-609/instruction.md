False positive List.concat hint
<!--- Provide a general summary of the issue in the Title above -->
![image](https://user-images.githubusercontent.com/1430958/121411590-16b7f800-c964-11eb-9dd1-8c039e31f17f.png)
```elm
test =
    let
        aList =
            if True then
                [ 2, 3 ]

            else
                []
    in
    List.concat
        [ [ 1 ]
        , aList
        , [ 4 ]
        ]
```

## Expected Behavior
<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->
No warnings.

## Current Behavior
<!--- If describing a bug, tell us what happens instead of the expected behavior -->
<!--- If suggesting a change/improvement, explain the difference from current behavior -->
ElmLS gives me a warning on the `List.concat` expression:

> You should just merge the arguments of `List.concat` to a single list. - ElmLS

## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug, -->
<!--- or ideas how to implement the addition or change -->
don't show warnings in these cases. (Optimize for having false negatives sometimes, instead of having false positives sometimes?)

## Steps to Reproduce (for bugs)
<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->
1. Paste the code above into e.g. VSCode and wait for ElmLS to scan the file & report warnings


## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* Version used: 2.1.0
* Editor used: VSCode 1.56
