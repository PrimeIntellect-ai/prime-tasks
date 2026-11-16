Missing security operation
I'm trying to add a security operation to a subset of routes. However, the `security` op isn't set on the paths.

```
	s.Route("/github", func(r chi.Router) {
		r.Group(func(r chi.Router) {
			r.Use(sessionMiddleware, nethttp.SecurityMiddleware(s.OpenAPICollector, "User", openapi3.SecurityScheme{
				APIKeySecurityScheme: &openapi3.APIKeySecurityScheme{
					In:   "cookie",
					Name: appcfg.CookieName,
				},
			}))
			r.Method(http.MethodGet, "/connect", nethttp.NewHandler(controllers.Connect(appcfg.GitHubAppSlug), nethttp.SuccessStatus(http.StatusTemporaryRedirect)))
			r.Method(http.MethodGet, "/install", nethttp.NewHandler(controllers.Install(orgManager, clientCreator), nethttp.SuccessfulResponseContentType("text/html")))
		})
	})
```

Output of json (no security :()

```
    "/github/connect": {
      "get": {
        "summary": "Connect",
        "description": "Connect to GitHub",
        "operationId": "function/controllers.Connect",
        "responses": {
          "307": {
            "description": "Temporary Redirect",
            "headers": {
              "Location": {
                "style": "simple",
                "description": "Redirect to GitHub",
                "schema": {
                  "type": "string",
                  "description": "Redirect to GitHub"
                }
              }
            }
          },
          "400": {
            "description": "Bad Request",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/RestErrResponse"
                }
              }
            }
          }
        }
      }
    },
```

### Additional contract requirements

When security middleware adds an operation-level security requirement, the corresponding supplied security scheme must also be declared in the OpenAPI components under its configured name.
