[bug]: multiline ternary throws parser error
### Description of the bug

When trying this against a codebase I got this error even though this works fine with terraform (which hopefully follows the standard).

### Steps To Reproduce

tf file:
```tf
resource "google_pubsub_subscription" "to_ctrl_subscriptions" {
  topic   = "pre-prod-${each.value.tenant}+${each.value.space}-v1-${
    each.value.tenant == "tenant1" && each.value.space == "1" ? "2331240" :
    each.value.tenant == "tenant2" && each.value.space == "3" ? "9231231" :
    each.value.tenant == "tenant3" && each.value.space == "2" ? "r32345d0" :
    each.value.tenant == "tenant4" && each.value.space == "4" ? "123jfvri4" : ""
  }"
}
```
error:
```
Error discovering modules: Failed to parse HCL in module 'pubsub/modules/pubsub':    --> HCL parse error in line 201, column 71
    |
201 |     each.value.tenant == "tenant1" && each.value.space == "1" ? "2331240" :
    |                                                                                                                                ^---
    |
    = invalid expression; expected `"`, `[`, `{`, `-`, `!`, `(`, `_`, `<`, letter or digit
```

### Additional Information

_No response_
