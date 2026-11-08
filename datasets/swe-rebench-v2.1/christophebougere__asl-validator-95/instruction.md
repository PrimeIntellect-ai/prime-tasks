detect duplicate field names in payload templates resulting from substitution
**Is your feature request related to a problem? Please describe.**
Need a new rule to detect duplicate field names in a payload template following the rename that occurs after evaluation.

**Describe the solution you'd like**
Add a new validator that detects names that will collide.

invalid:
```json
"Parameters" : {
    "static": "foo",
   "static.$": "$.path.to.value"
}
```

The above is valid JSON at the time of deploy but will be invalid after evaluation since `static.$` is renamed to `static` which collides with the existing field.
