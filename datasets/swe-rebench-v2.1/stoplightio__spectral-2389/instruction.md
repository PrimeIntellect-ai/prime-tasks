spectral custom rule attribute "field" not reset when invoking multiple functions on single rule.
**Describe the bug**
 `field` attribute is not cleared when multiple functions used in same rule. Same behavior on both CLI and JS invocation.

The VS Code extension seems to not have this same defect.

**To Reproduce**

* Given this OpenAPI/AsyncAPI document '...'
```
Example1:
  title: Example1
  description: Example1
  type: string
  enum:
    - enum11
    - enum12
  example: enum12
Example2:
  title: Example2
  description: Example2
  type: string
  enum:
    - enum21
    - enum22
  example: enum22
```

* And this spectral rule:
```
functions: [Rules]
rules:
  bug-fields:
    given: "$.*"
    then:
      - function: Rules
        functionOptions:
          rules:
            - Print1
      - field: "title"
        function: Rules
        functionOptions:
          rules:
            - Print2
 ```
(Where the function "Rules" invokes the sub-function/rule specified in "rules")

* With JS those custom functions defined simply as:
```
function Print1(results, input, path, rule) {
    console.log("Print1", path)
}
function Print2(results, input, path, rule) {
    console.log("Print2", path)
}
```

* Invoked both in CLI and JS, result via console is:

`npx spectral lint --ruleset .spectral.yaml .\placeholder.yaml --verbose`


```
Print1 [ 'Example1' ]
Print2 [ 'Example1', 'title' ]
Print1 [ 'Example2' ]
Print2 [ 'Example2', 'title' ]
```

However, the issue occurs if I include the "field" attribute to the first entry, instead of the second, like so:
```
  bug-fields:
    given: "$.*"
    then:
      - field: "title"
        function: Rules
        functionOptions:
          rules:
            - Print1
      - function: Rules
        functionOptions:
          rules:
            - Print2
```

**Expected behavior**

`field` attribute is only applied to the function where it is defined.

In the VS Code Spectral Extension, this is also what happens.

```
Print1 [ 'Example1', 'title' ]
Print2 [ 'Example1' ]
Print1 [ 'Example2', 'title' ]
Print2 [ 'Example2' ]
```

**Observed output**

`field` attribute is not cleared when invoking the Print2 function, resulting in the execution order of these separate functions influencing each other. Which I assume is not intended behavior.

```
Print1 [ 'Example1', 'title' ]
Print2 [ 'Example1', 'title' ]
Print1 [ 'Example2', 'title' ]
Print2 [ 'Example2', 'title' ]
```


**Environment (remove any that are not applicable):**
 - Library version: 6.6.0
 - OS: Windows 11
 - VS Code Spectral Extension: Spectral  v1.1.0


Let me know if I need to provide more information to clarify!
