[Bug] SyncedCachedEnforcer: RUnlock of unlocked RWMutex
**Want to prioritize this issue? Try:**

[![issuehunt-to-marktext](https://github.com/BoostIO/issuehunt-materials/raw/master/v1/issuehunt-button-v1.svg)](https://issuehunt.io/r/casbin/casbin)

------

**Describe the bug**
Fatal error during runtime.
```
api[586577]: fatal error: sync: RUnlock of unlocked RWMutex
api[586577]: goroutine 564104007 [running]:
api[586577]: sync.fatal({0x28eb0d0?, 0x31db0e67170?})
api[586577]:         runtime/panic.go:1031 +0x1e
api[586577]: sync.(*RWMutex).rUnlockSlow(0xc00fd992a8, 0xabc4a2d0?)
api[586577]:         sync/rwmutex.go:129 +0x39
api[586577]: sync.(*RWMutex).RUnlock(...)
api[586577]:         sync/rwmutex.go:119
api[586577]: github.com/casbin/casbin/v2/persist/cache.(*SyncCache).Get(0xc00fd992a0, {0xc7acc054a0, 0x5d})
api[586577]:         github.com/casbin/casbin/v2@v2.66.1/persist/cache/cache_sync.go:45 +0x145
api[586577]: github.com/casbin/casbin/v2.(*SyncedCachedEnforcer).getCachedResult(...)
api[586577]:         github.com/casbin/casbin/v2@v2.66.1/enforcer_cached_synced.go:123
api[586577]: github.com/casbin/casbin/v2.(*SyncedCachedEnforcer).Enforce(0xc0f71a3f50, {0x2e01a593c40, 0x4, 0x4})
api[586577]:         github.com/casbin/casbin/v2@v2.66.1/enforcer_cached_synced.go:70 +0x85
```

**To Reproduce**
Steps to reproduce the behavior:
1. Use SyncedCachedEnforcer

**Expected behavior**
No crash
