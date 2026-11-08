False Positives on disallowedFunctionCalls Rule in Version 4.1.1
# Description
## Summary:
After upgrading from version `4.0.1` to `4.1.1`, the `disallowedFunctionCalls` rule produces false positives when certain strings are present in method names, incorrectly identifying them as forbidden function calls.

## Steps to Reproduce:

Configure `disallowedFunctionCalls` as follows:
```yaml
parameters:
  disallowedFunctionCalls:
    - function:
        - 'data_get()'
        - 'data_set()'
        - 'optional()'
      message: 'This function is not allowed'
```
Define a method or function with a name that includes the substring of a forbidden function, such as `testItHandlesSomeOptional()`.
Run `PHPStan` analysis.

## Observed Behavior:
PHPStan flags the method as violating the `disallowedFunctionCalls` rule:
```yaml
message: '#^Calling optional\(\) is forbidden, This function is not allowed\.$#'
```

## Expected Behavior:
`PHPStan` should not flag method or function names that merely include substrings matching forbidden function names. Only actual calls to the forbidden functions should trigger a violation.

## Environment:

PHPStan version: 2.1.1
spaze/phpstan-disallowed-calls: 4.1.1
Previous working version: 4.0.1

## Additional Notes:

This appears to be a regression introduced in version `4.1.1`. The pattern matching for the `disallowedFunctionCalls` rule seems to be overly aggressive, treating method or function names as if they were calls to the forbidden functions.

Let me know if more details are needed!
