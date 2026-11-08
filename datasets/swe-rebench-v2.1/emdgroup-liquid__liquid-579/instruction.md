bug: ld-label without child element throws error on click
### Prerequisites

- [X] I know [how to contribute a proper bug report](https://github.com/emdgroup-liquid/liquid/blob/main/CONTRIBUTING.md#reporting-bugs).
- [X] I agree to follow the [Code of Conduct](https://github.com/emdgroup-liquid/liquid/blob/main/CODE_OF_CONDUCT.md).
- [X] I have searched for [existing issues](https://github.com/emdgroup-liquid/liquid/issues?q=is%3Aopen+is%3Aissue+label%3Abug) that already report this problem, without success.

### Liquid version

4.7.9

### Framework bindings

no bindings

### Current behavior

```
Uncaught (in promise) TypeError: Cannot read properties of null (reading 'contains')
    at LdLabel.handleClick (ld-label.tsx:37:20)
```

### Expected behavior

No error.

### Steps to reproduce

1. Create a `ld-label` component with just plain text content.
2. Click it and check the logs.

### Code reproduction URL

https://stackblitz.com/edit/github-ngt6cj?file=index.html

### Additional information

_No response_
