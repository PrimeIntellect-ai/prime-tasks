Feature Request - Also return almanac after engine.run()
I have a use case where as I run rules, I sometimes need to add or update runtime facts.

For a logical example, I have something like this:

```
Rule 1:
IF fact1 > 1000 (+ more conditions) => set fact1 to fact1 - 100
Rule 2:
IF fact1 > 1500 (+ other conditions) => set fact1 to fact1 - 100
etc...
```

After the engine run, I need to know what the eventual value of `fact1` has become.  There are ways I can do this currently, but it would be far easier if I had access to the almanac after the engine run.

I could create a PR to accomplish this, but before I do, I have a couple questions:

1. Is this something that should be supported by the engine?  Am I overlooking something?
2. Any recommendations on how to do this without introducing a breaking change?  Or is that not possible?

### Additional contract requirements

After `Engine.run` completes, its resolved result exposes the almanac used for that execution through an `almanac` property.
