Cognitive complexity adds incorrect nesting for if-else chains
**Describe the bug**

Currently, an if-else chain will increase the nesting level and add the nesting increment for every addition `else if` statement in an if-else chain. This is incorrect behaviour; an `else if` statement should increment complexity by 1 (regardless of current nesting level) and leave the nesting level as-is.

For example, the following should yield a total complexity of 5:
```
    for { // +1
        if a { // +2 (nesting = 1)
            foo()
        } else if b { // +1
            bar()
        } else if c { // +1
            baz()
        }
    }
```
but the current implementation incorrectly increments the nesting level with each `else if` and adds the nesting increment where it shouldn't:
```
    for { // +1
        if a { // +2 (nesting = 1)
            foo()
        } else if b { // +3 (nesting = 2)
            bar()
        } else if c { // +4 (nesting = 3)
            baz()
        }
    }
```
