Dates created before useFakeTimers aren't seen as instanceof Date anymore
-   FakeTimers version : @sinonjs/fake-timers@13.0.1
-   Environment : nodejs
-   Example URL : <!-- If you have one, such as a jsbin -->
-   Other libraries you are using: node-opcua, sinon@19.0.0

**What did you expect to happen?**

Date object that have been created before fakeTimer takes actions should still be instanceof Date, as it used to be in previous versions


**What actually happens**


**How to reproduce**

npm install sinon@19

```javascript
 import sinon from "sinon";


 // defined before useFakeTimers
 const minDate = new Date(Date.UTC(1601, 0, 1, 0, 0, 0));
 console.log("minDate instanceof Date (before)", minDate instanceof Date);
 const clock = sinon.useFakeTimers();
 const d = new Date();
 console.log("instanceof Date", d instanceof Date);

 console.log("minDate instanceof Date (after) : should be true but is : ", minDate instanceof Date);

 clock.restore();
```

```javascript
// without using sinon
import FakeTimers from "@sinonjs/fake-timers";

// emulating what sinonjs is doing:
function createClock(config, globalCtx) {
    let FakeTimersCtx = FakeTimers;
    if (globalCtx !== null && typeof globalCtx === "object") {
        FakeTimersCtx = FakeTimers.withGlobal(globalCtx);
    }
    const clock = FakeTimersCtx.install(config);
    clock.restore = clock.uninstall;
    return clock;
}

 // defined before useFakeTimers
 const minDate = new Date(Date.UTC(1601, 0, 1, 0, 0, 0));
 console.log("minDate instanceof Date (before)", minDate instanceof Date);

var clock = createClock();
 const d = new Date();
 console.log("instanceof Date", d instanceof Date);

 console.log("minDate instanceof Date (after) : should be true but is : ", minDate instanceof Date);

 clock.restore();

```
