URLs with multiple query parameters escape the `&` delimiter incorrectly
Example the following test case exists which tests 1 query parameter
```golang
{
    in:       `<a href="?q=1">`,
    expected: `<a href="?q=1" rel="nofollow">`,
},
```

Add the following test case to produce a failure with more than one query parameter.
```golang
{
    in:       `<a href="?q=1&r=2">`,
    expected: `<a href="?q=1&r=2" rel="nofollow">`,
},
```

the result would be `<a href="?q=1&amp;r=2" rel="nofollow">` which breaks the queries

### Additional contract requirements

- For `<a href="?q=1&r=2&s=:foo@">`, the sanitized output must be `<a href="?q=1&r=2&s=%3Afoo%40" rel="nofollow">`.
