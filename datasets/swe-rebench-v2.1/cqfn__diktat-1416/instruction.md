LongLine rule doesnt fix long complex expression
## Describe the bug

### Initial code:
```kotlin
attrs.disabled = (selfRole == Role.OWNER && isSelfRecord(props.selfUserInfo, user)) || !(selfRole.isHigherOrEqualThan(Role.OWNER) || userRole.isLowerThan(selfRole))
```
Error message - ([LONG_LINE] this line is longer than allowed: max line length 180, but was 196)

## Expected behavior

### Expected code:
```kotlin
attrs.disabled = (selfRole == Role.OWNER && isSelfRecord(props.selfUserInfo, user)) || !(selfRole.isHigherOrEqualThan(Role.OWNER) ||
userRole.isLowerThan(selfRole))
```

## Observed behavior
### Observed code:

```kotlin
attrs.disabled = (selfRole == Role.OWNER && isSelfRecord(props.selfUserInfo, user)) || !(selfRole.isHigherOrEqualThan(Role.OWNER) || userRole.isLowerThan(selfRole))
```

## Environment information
* diktat version: 1.2.0
