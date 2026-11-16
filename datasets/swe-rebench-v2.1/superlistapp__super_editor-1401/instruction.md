[attributed_text] AttributedSpans.hasAttributionsWithin incorrectly throws as it incorrectly iterates over a Set of attributes
The method AttributedSpans.hasAttributionsWithin [HIDDEN] This throws an exception (ConcurrentModificationError) [HIDDEN] This is a simple algorithmic bug / invalid usage of a set and it's iterator.

Here is the fix for this issue: https://github.com/superlistapp/super_editor/pull/1202
(previous pull request without a unit test was: https://github.com/superlistapp/super_editor/pull/1188)

### Additional contract requirements

- A call to `AttributedSpans.hasAttributionsWithin` with multiple requested attributions must complete without throwing a concurrent-modification exception. It returns true when every requested attribution is present within the specified range, and false when any requested attribution is absent from that range.
