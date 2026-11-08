Include ticks in countTimers
<!--
Are you wondering how to do something with Lolex, or something else that is purely
usage related? Please post it to StackOverflow using the `sinon` and `lolex` labels.
This makes it possible for the bigger community to help answer your questions.

The issue tracker is solely meant for posting bugs, feature requests and non-usage related issues.
-->

> We understand you have a problem and are in a hurry, but please provide us with some info to make it much more likely for your issue to be understood, worked on and resolved quickly.


* Lolex version : 4.0.1
* Environment   : Node 10
* Example URL   : N/A
* Other libraries you are using: N/A

**What did you expect to happen?**
See https://github.com/facebook/jest/pull/8139 for justification. Tl;dr; is that a timer count should include all scheduled timers _and friends_, not just timers.

**What actually happens**

`clock.nextTick` does not contribute to the count

**How to reproduce**

```js
const lolex = require("lolex");

const clock = lolex.createClock();

clock.setTimeout(() => {}, 5);
clock.nextTick(() => {});

console.log(clock.countTimers()); // 1
```
