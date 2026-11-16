bug: findOne returns an object when it should not
Howdy!

I've been using TypeDORM in one of my projects recently, and it has been good so far! Except for one problem: even when there is no item with a primary key in a table, EntityManager will always return an object (although empty). This breaks some other things, like `EntityManager.exists` and other places in the library that may depend on those functions somehow.

https://github.com/typedorm/typedorm/blob/6ccc93e376905a82412f09d7bb62f29bb5ea57fb/packages/core/src/classes/manager/entity-manager.ts#L153-L158

[HIDDEN] The result is that the function does not really comply with its interface, and the `Promise<Entity | undefined>` return type is really just `Promise<Entity | {}>`, which is... not ideal, to say the least (as it will potentially and inadvertently break invariants of the entity class, which the library have no knowledge of, for obvious reasons).

In my application, I use `EntityManager.exists` with a primary key (PK + SK) to check for the existence of an entity, and to determine whether to call create or update. But because `EntityManager.findOne` always returns an object even when the primary key does not exist, `EntityManager.exists` in turn will always return true:
 https://github.com/typedorm/typedorm/blob/6ccc93e376905a82412f09d7bb62f29bb5ea57fb/packages/core/src/classes/manager/entity-manager.ts#L215-L217

Perhaps `EntityManager.findOne`'s implementation should really end up like so:

```ts
    // ...
    [HIDDEN]
  }
```

But I may be wrong, hence why I opened this issue. Is my analysis correct?

### Additional contract requirements

- `EntityManager.findOne` returns `undefined` when no item exists for the requested primary key. `EntityManager.exists` returns `false` when no item exists.
