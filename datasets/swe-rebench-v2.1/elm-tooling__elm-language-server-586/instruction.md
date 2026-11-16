Renaming custom type constructors also renames imported modules when names match
When trying to rename a custom type constructor whose name matches one of the imported module names, the imported module name gets renamed along with the constructor.

Take following minimal example:
```elm
module Test exposing (..)

import Html

type Model = Html

value : Model
value = Html

view : Html.Html msg
view = Html.p [] []
```

When you rename the constructor `Html` in VSCode, you currently end up with the following result:

```elm
module Test exposing (..)

import Foo -- this is incorrect, this has to remain `Html`

type Model = Foo

value : Model
value = Foo

view : Html.Html msg
view = Html.p [] []
```

## Expected Behavior
Renaming a constructor should rename only the constructor along with all the usages of the constructor.

## Current Behavior
Renaming a constructor renames not only the constructor and all the usages of the constructor but also _unrelated but identically named imports_.

## Possible Solution
???

## Steps to Reproduce (for bugs)
1. Paste the minimal example from this description in a new module in VSCode.
2. Use the rename action in VSCode to rename the `Html` constructor, rename it to something different.

=> `import Html` line will be incorrectly renamed

## Context
I was trying to rename a value constructor.

## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* Version used: 2.1.0
* Editor used: VSCode 1.55.2
* Environment name and version (e.g. node.js 5.4): node 12.20.1
* Operating System and version: Darwin x64 19.6.0 (OSX 10.15.7)
