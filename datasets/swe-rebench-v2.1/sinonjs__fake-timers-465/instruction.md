[Feature] Jump forward in time to simulate throttled timers
> We understand you have a problem and are in a hurry, but please provide us with some info to make it much more likely for your issue to be understood, worked on and resolved quickly.

-   FakeTimers version : 10.0.0
-   Environment : Jest/JSDOM
-   Example URL : N/A
-   Other libraries you are using: N/A

**What did you expect to happen?**

I expected there would be an API to enable skipping forward in time in a similar way that [browsers will throttle a `setInterval` when the page is backgrounded](https://developer.chrome.com/blog/timer-throttling-in-chrome-88/). That is to say, if I have the following code:

```js
setInterval(() => {
    console.log("Here");
}, 100);
```

This would print 10 times a second. So running `clock.tick(2000)` would print this 20 times. I expected that there would be a `clock.jump(2000)` which would print this only once, effectively advancing the clock without any intermediary tasks in the event loop being processed. Another way to look at it is that all pending tasks were throttled to whatever value is passed to the `clock.jump` method.

**What actually happens**

There currently is no way to test code which is written to handle this browser behavior of throttling timers.

**How to reproduce**

N/A
