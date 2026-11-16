Move Footnotes to the bottom: inserts extra 2 blank lines every time you run it
Move Footnotes to the bottom keeps adding an extra two blank line above the footnotes each time you run Linter.

Before:
```
A sentence about stuff.[^1]

[^1]: A reference about stuff.
```

After first run of Linter:
```
A sentence about stuff.[^1]



[^1]: A reference about stuff.
```

After second run of Linter:
```
A sentence about stuff.[^1]





[^1]: A reference about stuff.
```

After third run of Linter:

```
A sentence about stuff.[^1]







[^1]: A reference about stuff.
```

And so on. Thanks for your help!
Laura
