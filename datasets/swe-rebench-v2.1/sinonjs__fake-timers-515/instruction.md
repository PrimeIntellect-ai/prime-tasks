Support `performance.timeOrigin` property
> We understand you have a problem and are in a hurry, but please provide us with some info to make it much more likely for your issue to be understood, worked on and resolved quickly.

-   FakeTimers version : 13.0.5
-   Environment : MacOS
-   Other libraries you are using: jest, @sentry/react

**What did you expect to happen?**

I expected that `performance.timeOrigin` (https://developer.mozilla.org/en-US/docs/Web/API/Performance/timeOrigin) would return a valid value with fake timers enabled in jest.

**What actually happens**

`performance.timeOrigin` is set to NOOP [here](https://github.com/sinonjs/fake-timers/blob/7861c930e8f9aaa9d227431623cc82347aff0291/src/fake-timers-src.js#L1843).

**How to reproduce**

```bash
git clone https://github.com/rriski/fake-timers-timeOrigin-repro.git
npm run test
# --> test fails
# Uncomment `doNotFake` in jest.config.js
npm run test
# --> test passes
```

**Additional information**

* Related to #493
* `@sentry/react` uses the performance API to set the session starting time, see [session.ts](https://github.com/getsentry/sentry-javascript/blob/6331d7ced7373e3f351ffacb71af54392c19acda/packages/core/src/session.ts#L14)

### Additional contract requirements

- With fake timers installed, `performance.timeOrigin` is a numeric timestamp (milliseconds) for the fake performance clock's origin.
- When `now` is given to `install()`, that value is the origin. When `now` is not given, the origin is the default epoch (`0`).
