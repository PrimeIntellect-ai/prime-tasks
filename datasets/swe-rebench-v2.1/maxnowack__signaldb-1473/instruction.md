[Bug] Debounce skips pushes
Heya,

Thanks for this library, been really enjoying diving into it.

However, I've noticed that when I do multiple actions on different collections at once (e.g. insert multiple rows in different tables straight after each other), some of those actions don't get synced.

I think I've narrowed it down to how the pushes are debounced in the sync manager:

from https://github.com/maxnowack/signaldb/blob/5760bb15f4eebf3a5fb772d28f3304832d685620/packages/base/sync/src/SyncManager.ts#L314:

```typescript
protected deboucedPush = debounce((name: string) => {
    this.pushChanges(name).catch(() => { /* error handler is called in sync */ })
  }, 100)

  protected schedulePush(name: string) {
    this.deboucedPush(name)
  }
```

It looks like `debounce` will skip the first few few inserts, and only perform the last one, as the same `debouncedPush` function  is used for all collections in the sync manager.

For now i could make a separate sync manager per collection as a workaround, but this should be fairly easy to fix.
