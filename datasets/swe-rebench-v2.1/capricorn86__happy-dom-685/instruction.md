regression: assign of window.location.href
**Describe the bug**
A clear and concise description of what the bug is.

Starting with version 7.8.0, setting the `href` property like this:
```
window.location.href = '/foo'
```

Will throw an exception: `ERR_INVALID_URL`.

**To Reproduce**
Steps to reproduce the behavior:
1. Create a test with happy-dom
2. In the test, insert `window.location.href = '/foo'`
3. See error `ERR_INVALID_URL`

**Expected behavior**
I can set the `href` property using a string which doest not represent a full url, in the same exact way in which both chrome and firefox works.

**Screenshots**
<img width="548" alt="image" src="https://user-images.githubusercontent.com/6383527/206861764-f38db7fe-d3a8-4303-90a2-abd4cf6767ce.png">

**Device:**
 - OS: OS X
 - Browser: Vitest
 - Version: v0.25.6

**Additional context**
This happens using happy-dom during tests.
