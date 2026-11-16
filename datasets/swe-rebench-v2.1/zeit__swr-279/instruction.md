[Question]: is it as designed that trigger and mutate will follow dedupingInterval
Hey,

small question: is it as designed, that a manual trigger will follow the `dedupingInterval` and don't invalidate the cached item if it was less than the `dedupingInterval`?

Example: https://codesandbox.io/s/quirky-albattani-ttfrw

Expected: On each button click the new time will be fetched

Actual: It only will be fetched if I click slower than 200ms (default `dedupingInterval`)

Version: 0.1.17
