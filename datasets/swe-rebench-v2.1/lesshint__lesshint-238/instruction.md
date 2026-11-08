urlFormat and urlQuotes only checks the first URL in a declaration
When declaring multiple URLs, for example:
```less
background-image: url(http://example.com/img/image.jpg), url(http://example.com/img/image2.jpg);
```

With this config:
```json
{
    "urlFormat": {
        "enabled": true,
        "style": "relative"
    },
    "urlQuotes": {
        "enabled": true
    }
}
```

Only the first URL will be reported by both linters.
