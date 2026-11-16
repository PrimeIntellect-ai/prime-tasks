bug(middleware/persist): using new storage option with createJSONStorage causes subscription to fire early (regression)
## Summary

using old `getStorage` option would not fire subscriptions when retrieving the state from storage for the first time, but `storage` does

## Link to reproduction

old: https://codesandbox.io/s/autumn-fog-400vf4
new: https://codesandbox.io/s/happy-carson-0teelt

## Check List

- [x] I've already opened a [discussion](https://github.com/pmndrs/zustand/discussions) before opening this issue.
