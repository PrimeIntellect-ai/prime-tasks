Lint flags endpoints that exist as not existing
### Description

The following sysl file:
```
AppOne:
    EndpointOne:
        AppTwo <- EndpointTwo

AppTwo:
    EndpointTwo:
        ...
```

Displays the following output for `sysl validate`:
```
WARN[0000] lint lint_simple.sysl:3:8: Endpoint 'EndpointTwo' does not exist for call 'AppTwo <- EndpointTwo'
```

### Expected behavior

No lint errors.

### Actual behavior

The above lint error is displayed.
