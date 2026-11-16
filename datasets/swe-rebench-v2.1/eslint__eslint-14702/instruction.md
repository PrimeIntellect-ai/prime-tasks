no-fallthrough should allow the comment inside of a block when the case is a single block
**What rule do you want to change?**

no-fallthrough

**Does this change cause the rule to produce more or fewer warnings?**

fewer

**How will the change be implemented? (New option, new default behavior, etc.)?**

new default behavior

**Please provide some example code that this change will affect:**

<!-- Put your code examples here -->
```js
switch (foo) {
  case 1: {
    let x = value;
    console.log(value);
    // falls through
  }
  case 2: {
    doSomething();
  }
}
```

**What does the rule currently do for this code?**

Error

**What will the rule do after it's changed?**

Not error

**Are you willing to submit a pull request to implement this change?**

Yes

---

This has been brought up before, in #9559 and #9080, and with a PR in #11016. On each of those occasions it's been closed automatically without any interest. But those just asked for the new behavior without really explaining why.

I want to make a case the proposed change is **the right behavior**. The `fallthrough` comment is intended to replace a `break`, which means that a reader of the code will be looking for it where they would expect to find the `break`. And the convention when using a braced `case` is that the `break` occurs _within_ the braces, not outside of it. So that is where a reader should expect to find the comment, not (as eslint currently requires) _after_ the braces. The placement required by the current rule actually makes the comment easier to miss.
