Route binding coupling
My OpenAPI definition has routes like:
```
PUT /v1/users/{id}
...
```

I use route binding, so routes looks like:
```
PUT /v1/users/{user}
```

My tests get no match for this route.

I'm getting around with some nasty `str_replace` 🤡
