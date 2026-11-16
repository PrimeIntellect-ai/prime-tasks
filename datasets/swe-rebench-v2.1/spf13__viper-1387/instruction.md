Accessing array slices fails for non-lowercase keys
### Preflight Checklist

- [X] I have searched the [issue tracker](https://www.github.com/spf13/viper/issues) for an issue that matches the one I want to file, without success.
- [X] I am not looking for support or already pursued the available [support channels](https://github.com/spf13/viper/issues/new/choose) without success.
- [X] I have checked the [troubleshooting guide](https://github.com/spf13/viper/blob/master/TROUBLESHOOTING.md) for my problem, without success.

### Viper Version

master

### Go Version

1.17.9

### Config Source

Files

### Format

YAML

### Repl.it link

_No response_

### Code reproducing the issue

```go
diff --git a/viper_test.go b/viper_test.go
index c41a1e7..536a53d 100644
--- a/viper_test.go
+++ b/viper_test.go
@@ -2517,6 +2517,7 @@ func TestKeyDelimiter(t *testing.T) {

 var yamlDeepNestedSlices = []byte(`TV:
 - title: "The expanse"
+  originalNetwork: "syfy"
   seasons:
   - first_released: "December 14, 2015"
     episodes:
@@ -2547,6 +2548,7 @@ func TestSliceIndexAccess(t *testing.T) {
        require.NoError(t, err)

        assert.Equal(t, "The expanse", v.GetString("tv.0.title"))
+       assert.Equal(t, "syfy", v.GetString("tv.0.originalNetwork"))
        assert.Equal(t, "February 1, 2017", v.GetString("tv.0.seasons.1.first_released"))
        assert.Equal(t, "Static", v.GetString("tv.0.seasons.1.episodes.2.title"))
        assert.Equal(t, "December 15, 2015", v.GetString("tv.0.seasons.0.episodes.1.air_date"))
```


### Expected Behavior

If my config contains an array, and one of the sub-keys in that array is non-lowercase (ie contains one or more capital letters), Viper is unable to retrieve the key using slice notation.

I modified a simple unit test to contain this array element:
```
- title: "The expanse"
  originalNetwork: "syfy"
  ```

When accessing the value with `v.GetString("tv.0.originalNetwork")`, I expect to receive the value "syfy".

### Actual Behavior

An empty string is returned.

### Steps To Reproduce

_No response_

### Additional Information

_No response_
