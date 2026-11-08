CacheSimple removes slots for same hash, different key.
### Change

CacheSimple invalidates the hash slot when the key hash matches even if it is a different key.

```
        Object key1 = new Object() { @Override public int hashCode() { return 0 ; } };
        Object key2 = new Object() { @Override public int hashCode() { return 0 ; } };
        Cache<Object, String> cache = CacheFactory.createSimpleCache(16);
        cache.put(key1, "object1");
        cache.put(key2, null);
        String s = cache.getIfPresent(key1);
        System.out.println(s);
        // s is null, should be "object1"
```
This is functionally safe - it just looses the cache entry unnecessarily.

### Are you interested in contributing a pull request for this task?

Yes
