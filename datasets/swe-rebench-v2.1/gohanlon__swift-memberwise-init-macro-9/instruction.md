Support `package` access modifier
### Description

Swift 5.9 has a new access modifier: `package` access ([SE-0386](https://github.com/apple/swift-evolution/blob/main/proposals/0386-package-access-modifier.md)).

(Thanks @davdroman, tracking #5.)

### Checklist

- [X] If possible, I've reproduced the issue using the `main` branch of this package.
- [X] This issue hasn't been addressed in an [existing GitHub issue](https://github.com/gohanlon/swift-memberwise-init-macro/issues) or [discussion](https://github.com/gohanlon/swift-memberwise-init-macro/discussions).

### Additional contract requirements

- Support the `.package` initializer-access configuration choice; it generates an initializer visible within the same package.
