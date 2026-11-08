toEither :: a -> b? -> Either a b
Suggested by @raine on [Gitter][1].

```javascript
> S.toEither('Invalid protocol', 'ftp://example.com/'.match(/^(http:|https:)[/][/]/))
Left("Invalid protocol")

> S.toEither('Invalid protocol', 'http://example.com/'.match(/^(http:|https:)[/][/]/))
Right(["http://", "http:"])
```

This would mirror [`S.toMaybe`][2].


[1]: https://gitter.im/plaid/sanctuary
[2]: https://github.com/plaid/sanctuary#toMaybe
