Make undefined an illegal cache value (for successful queries)
Please see [this discussion](https://github.com/tannerlinsley/react-query/discussions/2823)

This is an ever-recurring issue that you can't bail out of updates with `setQueryData`. But because the updater function gives you a potentially undefined value (if there is no cache entry for the key yet), TypeScript is very unhappy because you're supposed to create a new cache entry, and there is no "bailing out of it" because react-query actually creates the cache entry _before_ the functional updater of setQueryData is called.

### Proposed solution

As stated [here](https://github.com/tannerlinsley/react-query/discussions/2823#discussioncomment-1562184):

- let's allow the setQueryData functional updater to return undefined
  - signature: T | ((prev: T | undefined) => T | undefined)
  - if `undefined` is returned, we do not create or update the cache entry
  - that means if we have a previous value and `undefined` is returned - `undefined` is _not_ written to the cache, and observers are not informed about that.
  - this is technically breaking if `undefined` is a legit cache entry value for someone

This would be in-ine with what the `initialData` function already does: if `undefined` is returned from that, it is _not_ persisted to the cache.

Also, if a fetch function returns `undefined`, we should:
- transform it to a failed promise (error)
- warn during development mode about it

### Additional contract requirements

A query function's successful result type must exclude `undefined`; TypeScript should reject a query function declared to return `undefined`.
