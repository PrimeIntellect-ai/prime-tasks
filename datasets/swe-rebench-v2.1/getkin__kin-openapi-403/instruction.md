Resolving reference error happens with directories of different depths
Hi. I found the recursive lookup will fail when there are files in directories of different depths.

reporduce: https://github.com/stakme/kin-openapi/commit/cefedea2d71ad4ce07f2739ecbaea4c4f113f9cd

```
> go test github.com/getkin/kin-openapi/openapi3
--- FAIL: TestLoaderReadFromURIFunc (0.00s)
    loader_read_from_uri_func_test.go:20:
                Error Trace:    loader_read_from_uri_func_test.go:20
                Error:          Received unexpected error:
                                error resolving reference "../openapi.yml#/components/schemas/Bar": open testdata/recursiveRef/components/openapi.yml: no such file or directory
                Test:           TestLoaderReadFromURIFunc
--- FAIL: TestLoaderSupportsRecursiveReference (0.00s)
    loader_recursive_ref_test.go:13:
                Error Trace:    loader_recursive_ref_test.go:13
                Error:          Received unexpected error:
                                error resolving reference "../openapi.yml#/components/schemas/Bar": open testdata/recursiveRef/components/openapi.yml: no such file or directory
                Test:           TestLoaderSupportsRecursiveReference
FAIL
FAIL    github.com/getkin/kin-openapi/openapi3  0.192s
FAIL
```

[HIDDEN]

### Additional contract requirements

- The loader must successfully resolve recursive references when referenced files are in directories of different depths, including relative references encountered later in the reference chain.
