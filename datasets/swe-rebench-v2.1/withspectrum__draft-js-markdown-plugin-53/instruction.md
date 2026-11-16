replace ``` when exiting a code block
When closing a codeblock, hitting enter with this state:

````
[CODE]
last line of codeblock```[CURSOR]
[/CODE]
````

produces this state
````
[CODE]
last line of codeblock```
[/CODE]
[CURSOR]
````

when it should really remove the backticks like so

````
[CODE]
last line of codeblock
[/CODE]
[CURSOR]
````

Note: This only happens when the last line is not empty (when empty the backticks get removed)
