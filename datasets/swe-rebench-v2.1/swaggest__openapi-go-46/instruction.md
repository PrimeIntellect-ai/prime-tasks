Improving the regular expression used to remove gorilla.mux-style regexp in paths
Hello,
Imagine I have the 2 routes in my API : `/users/{userID:[^/]+}` and `/users/{userID:[^/]+}/books/{bookID:.+}`.
The regexp are `[^/]+` because without it, calling `users/toto/books/openapi`, matches with `/users/{userID:[^/]+}` with userID being `toto/books/openapi`.

The problem is that during `Spec.SetupOperation()`, `{userID:[^/]+}` is not matched by [HIDDEN].

I think changing the regex to `[HIDDEN]` would solve the problem.

### Additional contract requirements

- `Spec.SetupOperation()` must recognize the named path parameters in the illustrated routes even when their regexp constraints contain `/`, including `userID` and `bookID`.
