Type inference fails with functions picked by a selector
If the return parameter of a function returns another function you can not immediate call the returned function.

Reproducible with this nice oneliner:
```elm
Html.text <| .greeting { greeting = \name -> "Hello " ++ name ++ "!" } "John Doe"
```

## Expected Behavior
There should be no error on this place after opening/editing the document.

## Current Behavior
The error with following text will be generated beginning on .greeting until the end of the line:
```
Type mismatch error.
Expected: `String`
Found: `String -> String`
```

## Possible Solution
The error disappears if you change the code to this:
```elm
Html.text <| (.greeting { greeting = \name -> "Hello " ++ name ++ "!" }) "John Doe"
```
But `elm-format` will remove the unnecessary braces and the error appears again.

## Steps to Reproduce (for bugs)
1. Create a new elm project with language server configured.
2. Put in the main function the code from the first code block of this issue message.
3. The error is now shown.
4. If you put `.greeting { greeting = \name -> "Hello " ++ name ++ "!" }` enclosed within braces the error disappers.
5. Sometimes if you save the document the error disappears. I noticed, if elm-format changes the file then the error appears again.

You can also setup the language server with the usage example code of the ellie link below.

## Context
In my use case i use this for translations. If i want to format parameters in my translation i define it like followed:
```elm
english : Translations
english =
    { greeting = \name -> "Hello " ++ name ++ "!" }
```

Then i call a function which picks the right `Translation` record via a language parameter:
```
Html.text <| get English .greeting "John Doe"
```

The get function takes the `English` variant and applies `.greeting` on the `english` record. The get function returns in this case another function which takes a `String` which is immediately applied with the `"John Doe"` string literal. If the `get` call is not enclosed within braces then the language server generates an error.

You can find the sample code for my use case here: https://ellie-app.com/c7CPPGF2rQ5a1

## Your Environment
* Version used: 2.0.0
* Editor used: Visual Studio Code
```
Version: 1.52.1 (system setup)
Commit: ea3859d4ba2f3e577a159bc91e3074c5d85c0523
Datum: 2020-12-16T16:34:46.910Z
Electron: 9.3.5
Chrome: 83.0.4103.122
Node.js: 12.14.1
V8: 8.3.110.13-electron.0
Betriebssystem: Windows_NT x64 10.0.18363
```
* Environment name and version (e.g. node.js 5.4): node v13.10.1
* Operating System and version: Windows 10 Version 1909 (Build 18363.1316)
