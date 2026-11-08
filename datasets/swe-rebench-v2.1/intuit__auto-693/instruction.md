Incorrect commit message for version bumps
When running `auto shipit` using lerna, my commit message ends up being `Bump version to: %v [skip ci]` instead of `Bump version to: v.2.0.0 [skip ci]`

Looks like the problem is here: https://github.com/intuit/auto/blob/dbffbefcf35e902e22e654df9b28b4c7255d2599/plugins/npm/src/index.ts#L448

```js
          "'Bump version to: %v [skip ci]'",
```
should be
```js
          [HIDDEN]
```
[HIDDEN]

### Additional contract requirements

- When `auto shipit` uses lerna for a version bump, the commit message must contain the actual bumped version rather than the literal `%v`.
