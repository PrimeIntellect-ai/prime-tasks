Cannot set property 'hrtime' of undefined
Hello,

After migrating from lolex 1.4.0 to 1.5.0, my tests fails with this exception:
```javascript
     TypeError: Cannot set property 'hrtime' of undefined
      at uninstall (node_modules/lolex/src/lolex-src.js:360:39)
      at Object.clock.uninstall (node_modules/lolex/src/lolex-src.js:629:13)
      at bus.close.then.then (test/scheduling/testScheduler.js:64:57)
```

I'm using nodejs 6.2.0.

My tests use lolex this way:

Setup:
```javascript
clock = lolex.install(context)
```

Tear down:
```javascript
clock.uninstall()
```

[lolex-src.js 1.5.0](https://github.com/sinonjs/lolex/blob/v1.5.0/src/lolex-src.js#L360) seems to assume that the context object has a key named `process`.

Any idea regarding this ? Does this mean that compatibility was broken somehow ?
