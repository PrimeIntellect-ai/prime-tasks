RFC: Graphcache's query results to maintain structural equality
## Summary

We previously received numerous questions and requests regarding structural / deep-referential equality in Graphcache.

Currently, when a query is read from the normalised cache, Graphcache creates fresh objects and results each time. This means that even if we queried the cache twice while no data has changed, it would still create fresh objects all the way down. Graphcache is fast and can often read normalised data thousands of times each second. Even complex queries (many fragments and long lists) can often be read and written several hundreds of times per second. This typically puts us well into a small fraction of the typical "frame budget" of a web app (at 60FPS we'd just want to take up a fraction of 16.6ms!)

However, the same can't be said about rendering in apps. Often, rendering and updating the DOM and views may take exponentially longer for complex queries than querying this data from the cache. The typical wisdom is to avoid as much work as possible. This is why we often advised to write apps without any updates in mind, then check which part of an app is becoming too expensive to render, and adding strategic `React.memo` HOCs in React with `react-fast-compare` deep comparisons. This is **tedious** though and often still not optimal.

As, in the Web world, people are by now used to treating data as immutable and taking (deep) referential equality for granted, it's easier for us to implement it in Graphcache, rather than relying on users to hunt for excessive updates early on. While this isn't even recommended in the React community (the mantra being "let apps re-render, optimise later"), it's common for excessive updates to become confusing.

## Proposed Solution

Introduce a (weak) guarantee of structural / deep-equality. Given a previous result that Graphcache has generated from its normalised cache (or has just written to the cache when an API result comes in), use this previous result and reuse unchanged objects/data in the next result it generates.

[HIDDEN]

**⚠️ Limitation:** This solution focuses on update performance in UI frameworks at minimal cost to Graphcache itself. This means that if an entity is queried with the same selection set in two _different_ queries, they won't be referentially equal!

### Additional contract requirements

- When producing a subsequent result for a query, preserve the object identity of unchanged data from the prior result. Changed data must appear in the new result without mutating the prior result.
