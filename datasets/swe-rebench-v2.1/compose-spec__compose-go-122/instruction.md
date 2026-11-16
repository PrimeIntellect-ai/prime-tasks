service.pull_policy is ignored
`service.pull_policy` seems ignored.

The following test (base: e35895260882863269f36758f30b538101716841) does not work:
```diff
diff --git a/loader/loader_test.go b/loader/loader_test.go
index 49fa36e..5448520 100644
--- a/loader/loader_test.go
+++ b/loader/loader_test.go
@@ -1730,3 +1730,16 @@ services:
 `)
        assert.ErrorContains(t, err, "invalid string value for 'count' (the only value allowed is 'all')")
 }
+
+func TestServicePullPolicy(t *testing.T) {
+       actual, err := loadYAML(`
+services:
+  hello-world:
+    image: redis:alpine
+    pull_policy: always
+`)
+       assert.NilError(t, err)
+       svc, err := actual.GetService("hello-world")
+       assert.NilError(t, err)
+       assert.Equal(t, "always", svc.PullPolicy)
+}
```

```console
$ go test -run TestServicePullPolicy ./loader
--- FAIL: TestServicePullPolicy (0.01s)
    loader_test.go:1744: assertion failed: always (string) !=  (svc.PullPolicy string)
FAIL
FAIL    github.com/compose-spec/compose-go/loader       0.015s
FAIL
```
