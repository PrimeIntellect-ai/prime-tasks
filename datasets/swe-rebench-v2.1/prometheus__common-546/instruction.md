Authorization credentials should be optional
As part of [RFC9110](https://www.rfc-editor.org/rfc/rfc9110.html#name-introduction), authorization is defined in ABNF as:

```
Authorization = auth-scheme [ 1*SP ( token68 / [ auth-param *( OWS "," OWS auth-param ) ] ) ]
```

This means that the scheme MUST be provided but credentials are optional.
