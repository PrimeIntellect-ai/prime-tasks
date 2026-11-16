Bug: `natural` sort ignores `order`
### Describe the bug

Please see the self-explicit code example below.

### Code example

Configuration:
```ts
{
  type: 'natural',
  order: 'desc'
}
```

Code:
```ts
interface Test {
    a
    b
}
```

No error is reported.

### ESLint version

8.57.0

### ESLint Plugin Perfectionist version

4.1.2

### Additional comments

_No response_

### Validations

- [X] Read the [docs](https://perfectionist.dev).
- [X] Check that there isn't [already an issue](https://github.com/azat-io/eslint-plugin-perfectionist/issues) that reports the same bug to avoid creating a duplicate.
