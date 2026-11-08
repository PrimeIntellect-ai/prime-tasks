Psammead brand throws error if svg isnt provided
**Describe the bug**
If you don't provide a svg to @bbc/psammead-brand it throws an error. While it is currently a required prop, it should fail safe.

**To Reproduce**
Steps to reproduce the behavior:

1. Call the brand without an svg
2. See error `Cannot read property 'viewbox' of undefined`

**Expected behavior**
It fails gracefully, not throwing an error

- [x] Initially labelled with ["bug"](https://github.com/bbc/psammead/labels/bug)
