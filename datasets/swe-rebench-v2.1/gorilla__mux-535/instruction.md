[bug] CORSMethodMiddleware can add the allowed methods of the wrong routes
**Describe the bug**
When using `CORSMethodMiddleware` in a Subrouter it can add allowed methods from other routes that shouldn't be present.

[HIDDEN]

**Versions**
> Go version: `go version`
```
% go version
go version go1.12.1 darwin/amd64
```

> package version: run `git rev-parse HEAD` inside the repo

Sorry, I'm not using the repo of mux, but my `go.mod` has

`github.com/gorilla/mux v1.7.3`


**Steps to Reproduce**
> How can the bug be triggered?

Create a PathPrefix with a sub router, add two routes with paths where one is a substring of the other. Eg. `/hello` and `/hello/name`. Add different allowed methods to these routes.

You can see the allowed methods of both routes when requesting the route with the longer path.

Using the code example below the response header for `/test/hello/name` looks like

`Access-Control-Allow-Methods: GET,OPTIONS,POST,GET,OPTIONS`

**Expected behavior**
> What output or behaviour were you expecting instead?

I would expect to see only the allowed methods of the route in the `Access-Control-Allow-Methods` which would be `Access-Control-Allow-Methods: GET,OPTIONS`

**Code Snippets**
> A minimum viable code snippet can be useful! (use backticks to format it).
```golang
package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func Hello(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "Hello")
}

func HelloName(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "Hello")
}

func main() {
	router := mux.NewRouter().StrictSlash(true)

	subrouter := router.PathPrefix("/test").Subrouter()
	subrouter.HandleFunc("/hello", Hello).Methods(http.MethodGet, http.MethodOptions, http.MethodPost)
	subrouter.HandleFunc("/hello/{name}", HelloName).Methods(http.MethodGet, http.MethodOptions)

	subrouter.Use(mux.CORSMethodMiddleware(subrouter))

	http.ListenAndServe(":8081", router)
}

```
