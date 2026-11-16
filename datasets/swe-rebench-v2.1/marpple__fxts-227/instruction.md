bug: `join` If one numeric parameter is entered, it is returned as number type rather than string.
# Bug Report

<!--
  Please fill in each section completely. Thank you!
-->

### 💻 Code

<!-- Please post the relevant code sample here as well-->
<!-- How to reproduce it -->

```ts
const res = join("-", [1]);
console.log("res", res); // number type
```

### 🙁 Actual behavior

<!-- What happened, and why it was wrong -->

we expect number type

### 🙂 Expected behavior

<!-- What you expected to happen instead, and why -->

come string type

---

### Version Information

<!-- Please let me know your environment -->

- Operating system:
- Typescript:
- Nodejs:

### Additional contract requirements

- For `join("-", [1])`, the result must be the string `"1"`, not the number `1`. The “we expect number type” sentence in Actual behavior is incorrect; the expected result is a string.
