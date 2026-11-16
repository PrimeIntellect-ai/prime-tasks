Allow KeyLookup in Cookie for KeyAuth middleware
### Issue Description

It would be great if we could specify a cookie name for KeyLookup in the KeyAuth middleware config.
This way a user could pass the key credentials via a cookie, whereas now it is restricted to http headers, query params, and form fields.

Disclaimer: There might be good - security-related - reasons not to do this.

### Checklist


- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Expected behaviour

I can specify
```
KeyLookup: "cookie:<name>"
```
when defining KetAuthWithConfig, so the middleware reads the key from a cookie.

e.g.:

```
e := echo.New()
e.Use(middleware.KeyAuthWithConfig(middleware.KeyAuthConfig{
  KeyLookup: "cookie:api-key",
  Validator: func(key string, c echo.Context) (bool, error) {
               return key == "valid-key", nil
     },
}))
```

### Actual behaviour

Currently only following KeyLookup methods are allowed
```
"header:<name>"
"query:<name>"
"form:<name>"
```

### Steps to reproduce
n.A.

### Working code to debug

n.A.

### Version/commit
v4.3.0/7846e3f
