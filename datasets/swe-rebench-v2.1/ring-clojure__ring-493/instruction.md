Add support for Partitioned cookies (CHIPS)
Hey friends!

I'm looking to use [CHIPS](https://developer.mozilla.org/en-US/docs/Web/Privacy/Partitioned_cookies) in `:cookies`, but because the `set-cookie-attrs` is a private var, I can't add support for it myself:

https://github.com/ring-clojure/ring/blob/76e5d29128661225a08a9f8dfa7b07c83b6ed4da/ring-core/src/ring/middleware/cookies.clj#L21-L24

At the moment I'm using `alter-var-root` and `alter-meta` to gain access and insert it (see below), but that feels less good than maybe making it an atom and allowing it to be edited by users, or some other system that I trust y'all to come up with.

```clojure
(alter-meta! #'ring.middleware.cookies/set-cookie-attrs assoc :private false)
[HIDDEN]
```

### Additional contract requirements

- When a cookie in a Ring response's `:cookies` map has `:partitioned` set to `true`, its `Set-Cookie` value must include the `Partitioned` attribute.
