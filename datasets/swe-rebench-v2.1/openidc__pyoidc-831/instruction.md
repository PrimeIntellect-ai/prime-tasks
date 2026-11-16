birthdate miss lead a exception
Hi, im using pyoidc with [authing](https://www.authing.cn/)，if the app request scope included birthdate, and the provider do not reply a birthdate, it will go a exception as the `verify` do not check if it's a NoneType
```
  def verify(self, **kwargs):
        super().verify(**kwargs)

        if "birthdate" in self:
            # Either YYYY-MM-DD or just YYYY or 0000-MM-DD
            try:
                time.strptime(self["birthdate"], "%Y-%m-%d")
            except ValueError:
                try:
                    time.strptime(self["birthdate"], "%Y")
                except ValueError:
                    try:
                        time.strptime(self["birthdate"], "0000-%m-%d")
                    except ValueError:
                        raise VerificationError("Birthdate format error", self)
```

the userinfo returned by provider is something like this
```
'userinfo': {'name': None, 'nickname': None, 'birthdate': None ...}
```
actually i do not care for the `birthdate`, is there any work-around ?

### Additional contract requirements

- When `OpenIDSchema.from_json` parses a response containing a claim with JSON `null`, omit that claim from the resulting object. For these responses, `verify()` must return `True`.
