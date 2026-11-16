[Regression]: Test cases for Common are failing
## Potential Commit/PR that introduced the regression:
#1127, #1128

## Describe the regression:
`safe*` functions have been deprecated as default read and load functions are now safe by default.

## Steps to reproduce:
1. Run `npm test`.
2. Observe the test failures.

## Expected behavior:
1. All tests should pass seamlessly.

## Environment;

- Operating System(s): Linux/macOS/Windows [Variant and Version] - All
- Browser: Firefox/Chrome/Safari [Version] / Other (please specify) - N/A
