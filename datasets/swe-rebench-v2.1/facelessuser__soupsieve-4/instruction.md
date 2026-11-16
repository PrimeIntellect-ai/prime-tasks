Names of iter functions
Right now we have two iter functions `commentsiter` and `selectiter`. For 1.0, should they be called `comments_iter` and `select_iter`.  Or maybe `icomments` and `iselect`?

We have some flexibility before 1.0 release, so we should really settle on something. `commentsiter` and `selectiter` just seem hard to read.

### Additional contract requirements

Choose a clearer replacement name for each iterator. Either naming pair offered above is acceptable. The replacement comment and selector iterators must be available both as top-level convenience functions and from compiled selectors, and must preserve iteration behavior, including the existing result values and limit handling (zero or omitted means no limit).
