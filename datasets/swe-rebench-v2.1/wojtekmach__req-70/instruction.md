`auth`: Support bearer auth
curl example:

```bash
$ curl --fail -H "Authorization: Bearer foo" https://httpbin.org/bearer
{
  "authenticated": true,
  "token": "foo"
}
```

We should support:

```elixir
Req.get!("https://httpbin.org/bearer", auth: {:bearer, "foo"})
```
