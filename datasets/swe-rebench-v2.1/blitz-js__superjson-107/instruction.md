Error "Ambiguous class, provide a unique identifier" with next.js 10.0.6
We are having an issue with next.js 10.0.6 in Blitz where we get the `"Ambiguous class, provide a unique identifier"` error even though [all classes have unique ids](https://github.com/blitz-js/blitz/blob/canary/packages/core/src/errors.ts).

👉  https://github.com/blitz-js/blitz/pull/1828/checks?check_run_id=1795588783#step:9:104

**Possible fix:**

[HIDDEN]

### Additional contract requirements

- When a class is registered with an explicitly supplied identifier that is already registered for a different class, registration must not be rejected by the ambiguity check.
- When registering a class named `Car` whose identifier `Car` is already registered for a different class, registration must not fail with the ambiguity error and must emit `console.warn` with exactly `Ambiguous class "Car", provide a unique identifier.`
