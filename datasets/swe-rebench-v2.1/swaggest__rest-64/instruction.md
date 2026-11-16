Middlewares not working?
Hi,

I started to use this module in a project but I can't get most of the middlewares to work with the chi wrapper.

When I use the default chi router it works without problem (e.g with CORS and StipSlashes middlewares):

```go

r := chi.NewRouter()
r.Use(
middleware.StripSlashes,
cors.Handler(cors.Options{
			AllowedOrigins:   "*",
			AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
			AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
			AllowCredentials: false,
			MaxAge:           300,
		})
)
```

But with the wrapper it does not, as I am getting CORSed on preflight requests and end slashes are not stripped:

```go
r :=  chirouter.NewWrapper(chi.NewRouter())
r.Use(...) //Same as above
```

Do you have any idea why?

### Additional contract requirements

- If a handler passed to middleware implements `Foo()` and `nethttp.HandlerAs` can find `rest.HandlerWithRoute` on it, `nethttp.HandlerAs` must also be able to find its `Foo()` method.
