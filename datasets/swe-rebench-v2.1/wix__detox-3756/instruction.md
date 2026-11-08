withAncestor modifies original matcher
### What happened?

Calling `withAncestor` (and I suspect, `withDescendant`, and `and`), modifies the original selector it was called upon

### What was the expected behaviour?

I'd expect it to return a new instance of the matcher with the additional filtering applied, without overwriting the original. Overriding the original means that in a test suite, you can't easily share/reuse base matchers.

### Was it tested on latest Detox?

- [X] I have tested this issue on the latest Detox release and it still reproduces.

### Help us reproduce this issue!

Create some simple test with a reusable component, that is then used in two different ancestors, and write a test against that. The below will then show this problem:

```
const childComponent = by.id('child');
const parentComponentA = element(sharedComponent.withAncestor(by.id('parent-a')));

// Expected: MATCHER((id == “child” && ANCESTOR(id == “parent-a”))
// Actual: MATCHER((id == “child” && ANCESTOR(id == “parent-a”)) && ANCESTOR(id == “parent-b”))
const parentComponentB = element(childComponent.withAncestor(by.id('parentB')));
```

### In what environment did this happen?

Detox version: 19.3.0
React Native version: 0.69.6
Node version: 16.14.2
Test-runner (select one): jest-circus

### Detox logs

<details><summary>Detox logs</summary>

```
paste logs here!
```

</details>

### Device logs

<details><summary>Device logs</summary>

```
paste logs here!
```

</details>

### More data, please!

_No response_
