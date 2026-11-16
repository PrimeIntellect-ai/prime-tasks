Validator to check list level
This validator detects the too deeply nested list blocks as follows.

```
* level 1
  * level 2
     * level 3
       * level 4
          * level 5
...
```

### Additional contract requirements

The validator is publicly named `ListLevelValidator` and can be instantiated as a validator. Its accepted maximum list nesting depth is five: list elements at levels 1 through 5 do not produce an error, while an element deeper than level 5 is reported.
