AUR Version Service Test Failing
:clock11: **When did the problem start?**
~1 week ago, 2020 October 5th

<!-- Indicate when the problem started -->

:camera: **Live badge**

<!-- Provide a link to the live badge in plain text and markdown.  -->
https://img.shields.io/aur/version/spotify
![](https://img.shields.io/aur/version/spotify)

:wrench: **Is the live badge working?**
Yup

<!-- Indicate whether or not the live badge is working. -->

:link: **CircleCI link**
https://app.circleci.com/pipelines/github/badges/daily-tests/525/workflows/c7b1446c-783f-4483-98b0-4b00ba2b30f6/jobs/1423
<!-- Provide a link to the failing test in CircleCI. -->

:beetle: **Stack trace**

```
ValidationError: message mismatch: "value" with value "package not found" fails to match the required pattern: /^v\d+(\.\d+)*([-+~].*)?$/
    at Object.exports.process (node_modules/joi/lib/errors.js:184:16)
    at Object.internals.entry (node_modules/joi/lib/validator.js:150:26)
    at Object.exports.entry (node_modules/joi/lib/validator.js:27:30)
    at internals.Base.validate (node_modules/joi/lib/base.js:548:26)
    at Object.internals.assert (node_modules/joi/lib/index.js:225:27)
    at Object.attempt (node_modules/joi/lib/index.js:107:26)
    at Function._expectField (core/service-test-runner/icedfrisby-shields.js:73:13)
    at IcedFrisbyNock.<anonymous> (core/service-test-runner/icedfrisby-shields.js:54:26)
    at IcedFrisbyNock.<anonymous> (node_modules/icedfrisby/lib/icedfrisby.js:954:10)
    at invokeNextHook (node_modules/icedfrisby/lib/icedfrisby.js:1003:24)
    at /home/circleci/project/shields/node_modules/icedfrisby/lib/icedfrisby.js:1017:7
    at new Promise (<anonymous>)
    at IcedFrisbyNock._runHooks (node_modules/icedfrisby/lib/icedfrisby.js:976:12)
    at IcedFrisbyNock.run (node_modules/icedfrisby/lib/icedfrisby.js:1276:20)
    at processTicksAndRejections (internal/process/task_queues.js:97:5)
    at async Context.<anonymous> (node_modules/icedfrisby/lib/icedfrisby.js:1348:9)
```

:bulb: **Possible solution**
Few ways to fix this, I'm of two minds on how to best address.

For context, we use an orange color on the version badges for packages that have been flagged as out of date, which AIUI occurs when the package is out of date relative to the upstream source. The tricky part of using a live service test with this is finding a package that won't be removed (as happened with our current test target), but that will also be in an oudated state for a very long period of time.

I can try to find a new package that will hopefully meet that criteria, but also wonder if this may just be better suited to a unit test
<!--- Optional: only if you have suggestions on a fix/reason for the bug -->

<!-- Love Shields? Please consider donating $10 to sustain our activities:
👉  https://opencollective.com/shields -->

### Additional contract requirements

- The out-of-date version badge must render orange based on the package's out-of-date status, and this behavior must be verifiable without relying on a live AUR package remaining available or stale.
