[BUG] MethodNotAllowedHandler does not work for subrouter with different routes
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

> Go version: 1.20
    Mux version: 1.8.1

Starting with mux `v1.8.1` we encountered the following problem, which was not present in previous versions of the library.
If there are several routes in one subrouter, for example `/api` and `/api/{id}` MethodNotAllowedHandler does not work and NotFoundHandler is used by default.

An example test to reproduce the bug is shown below. The bug is not reproduced if:
- no subrouter is used, just main mux.Router
- subrouter contains only routes of the same type (only `/api` for example)
- place HandleFunc for `/api/{id}` before HandleFunc for `/api` in the code

[HIDDEN]

### Expected Behavior

Result 405 Method Not Allowed

### Steps To Reproduce

1. Run test:
```
func TestMiddlewareMethodMismatch(t *testing.T) {
	router := mux.NewRouter()
	router.MethodNotAllowedHandler = http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		rw.WriteHeader(http.StatusMethodNotAllowed)
		_, _ = rw.Write([]byte("Method not allowed"))
	})

	subrouter := router.PathPrefix("/v1").Subrouter()
	subrouter.HandleFunc("/api", func(w http.ResponseWriter, e *http.Request) {
		_, _ = w.Write([]byte("Logic"))
	}).Methods("GET")
	subrouter.HandleFunc("/api/{id}", func(w http.ResponseWriter, e *http.Request) {
		_, _ = w.Write([]byte("Logic"))
	}).Methods("GET")

	rw := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/v1/api", nil)
	router.ServeHTTP(rw, req)

	if rw.Code == http.StatusNotFound {
		t.Fatal("Not found instead of Method Not Allowed")
	}
}
```

### Anything else?

_No response_

### Additional contract requirements

- When a request's path matches a route in a subrouter with multiple distinct routes but its HTTP method does not match, dispatch the configured `MethodNotAllowedHandler` and return HTTP 405 rather than treating the request as not found.
