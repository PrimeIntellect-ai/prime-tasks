[bug] setting custom MethodNotAllowedHandler for subrouter returns 404s
**Describe the bug**
> When setting a custom MethodNotAllowedHandler for a Subrouter, a default `404 page not found` error is returned instead of the defined handler. Removing the custom handler makes a `405 method not found` return as normal.

…

**Versions**
> Go version: go1.12 darwin/amd64
> package version: 6137e193cdcba2725f16de84eaf0db2b769d9668

…


**Steps to Reproduce**
> Run a server with a subrouter, whose MethodNotAllowedHandler has been set a custom one. sending a `POST` to `http://localhost:3000/api/test` responses with `404 page not found`

…


**Expected behavior**
> the custom response `custom method not allowed` should be returned when trying to `POST` to `http://localhost:3000/api/test`

…

**Code Snippets**
here's a whole minimal server for your convenience:
```go
package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	router := mux.NewRouter()
	h := handler{}
	nah := notAllowedHandler{}

	apiRouter := router.PathPrefix("/api").Subrouter()
	apiRouter.MethodNotAllowedHandler = nah
	apiRouter.Handle("/test", h).Methods("GET")

	server := &http.Server{
		Addr:    ":3000",
		Handler: router,
	}

	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		fmt.Println("server shutdown:", err)
	}
}

type handler struct {
}

func (h handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "ok")
}

type notAllowedHandler struct {
}

func (h notAllowedHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusMethodNotAllowed)
	fmt.Fprint(w, "custom method not allowed")
}
```
…
