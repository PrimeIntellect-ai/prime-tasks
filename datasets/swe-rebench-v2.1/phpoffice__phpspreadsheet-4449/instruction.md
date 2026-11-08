Feature request: XML-Reader should recognize indents
Again, some minor feature request: The XML-Reader so far does not recognize indents. This can easily be fixed by [HIDDEN] in [HIDDEN]:

```
[HIDDEN]
    [HIDDEN]
    break;
```

And btw, thank you for your great work! Especially the XML reader makes my life so much easier.

### Additional contract requirements

- When an XML style specifies an indent, the XML reader must apply that value to the cell's alignment indent.
