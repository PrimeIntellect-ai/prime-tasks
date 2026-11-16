addLevel is not working
__pino 3.1.1__

This fails with: _TypeError: log.foo is not a function_

``` js
const pino = require('pino')
const log = pino()
log.addLevel('foo', 35)
log.foo('bar')
```


The tests does not show this because:
1. Levels added to one instance via the constructor will be added to new instances
2. Adding a level on the constructor works and there exists a test that verifies this. The test creates a new level with the options: `{level:'foo', levelVal: 35}`
3. The test that verifies `addLevel('foo', 35)` is working because it's executed __after__ the test in _(2)_, and because of _(1)_ it uses that function.

If the test in _(3)_ is modified to `addLevel('foo2', 35)`,  the test fails.

Here is some code to show the problem:

``` js
const log = pino({level:'foo', levelVal:35})
const log2 = pino()
log2.foo('should fail, but will work')
```


[HIDDEN]

Let me know if you want me to submit a PR.

### Additional contract requirements

- Custom level registration is local to a logger. A level supplied through constructor options or added with `addLevel` must not expose its method on, or alter the custom level definitions of, independently created logger instances.
