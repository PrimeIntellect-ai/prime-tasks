Tuplet setter doesn't inform client
Decided to document what I learned about the necessity of calling `coreElementsChanged()` when setting `.tuplets` directly.

Should spruce that up someday--there's not a good workaround if you're trying to *remove* tuplets, since `appendTuplet` only appends, and it breaks our principle that only core methods should require calling `coreElementsChanged()`.

_Originally posted by @jacobtylerwalls in https://github.com/cuthbertLab/music21/issues/958#issuecomment-818046530_

***

I see a few approaches:

- [HIDDEN] (I tried this and it broke a test, but the test may have been measuring the wrong thing, so it may unwravel some shoelaces that need to be unwraveled anyway)
- new method `removeTuplet` to address the gap in functionality
- clear tuplets in `Duration.clear()`

Not going to jump on this, doesn't seem urgent for v7.

### Additional contract requirements

After `Duration.tuplets` is assigned on an element in a stream, reading that stream's duration must reflect the new tuplets immediately, without a subsequent `coreElementsChanged()` call. This applies when tuplets are added, replaced, removed, or cleared.
