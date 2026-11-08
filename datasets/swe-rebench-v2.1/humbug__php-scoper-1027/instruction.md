Namespace being added to a numbered string
Came across this line:
```
$body = RegEx::replace('...(some).*?(regex)...', '\\1\\2', $body);
```

Which got replaced with:
```
$body = \MyPhpScoperPrefix\RegEx::replace('...(some).*?(regex)...', '\MyPhpScoperPrefix\\1\\2', $body);
```

I worked around this issue by adding this to my `scoper.inc.php`:
```
    'exclude-namespaces' => [
        ...
        '1'
    ],
```

But it is of course a bug.
