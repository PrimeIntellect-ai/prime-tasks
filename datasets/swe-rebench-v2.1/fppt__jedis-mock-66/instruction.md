Expire does not work as expected when data is set with hset()
Please note that I am not a Redis expert and that all the examples are in Kotlin.

In my application I got simple class to set hash which should expire after a given amount of time.

```
override fun method(key: String): String {
        return connectionPool.resource.use {
            it.hsetnx(key, HASH_CONST, UUID.randomUUID().toString())
            it.expire(key, EXPIRE_CONST)
            return it.hget(key, HASH_CONST)
        }
    }
```

I wrote a simple test which calls this method with given ID, then it waits more than the `EXPIRE_CONST` and then calls this method once again with same ID.

Result of this method should be different but it's the same.

After analyzing code of this library I saw that expire returns 0 instead of 1. [HIDDEN]
