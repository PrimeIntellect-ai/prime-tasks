Validation Provider access to invalid rules
**Versions**

- vee-validate: 2.1.7
- vue: 2.6.8

**Describe the bug**
I want to know which rule is invalid but i have only the error messages

**To reproduce**
Steps to reproduce the behavior:
1. Go to input
2. Fill with a basic string
3. See email error message and errors array

**Expected behavior**
The errors object is a basic array with errors messages but i can't access to the rule error to display custom message for example.

**Demo link**
[Codesandbox](https://codesandbox.io/s/r7yzx610y4?fontsize=14).

**Desktop (please complete the following information):**
 - OS: any
 - Browser any
 - Version any

**Smartphone (please complete the following information):**
 - Device: any
 - OS: any
 - Browser any
 - Version any

**Additional context**
There is a way to access to first or all rule and check if it's valid or invalid or maybe transform the errors array to a ErrorBag?

### Additional contract requirements

- The ValidationProvider scoped-slot context exposes a `failedRules` object keyed by each failed rule identifier, so consumers can identify which rule or rules failed for the current value.
