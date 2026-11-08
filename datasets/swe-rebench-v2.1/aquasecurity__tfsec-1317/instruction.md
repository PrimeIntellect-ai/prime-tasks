kubernetes_service_account automount_service_account_token bool triggers general-secrets-sensitive-in-attribute rule
When defining `kubernetes_service_account`, if you set the `automount_service_account_token` explicitly, it triggers the `general-secrets-sensitive-in-attribute` rule.

Example resource def:

```
resource "kubernetes_service_account" "rule_breaker" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  automount_service_account_token = "true"
}
```

Example output:

```
  Result 1

  [general-secrets-sensitive-in-attribute][CRITICAL] Block 'module.aws_serviceaccount:kubernetes_service_account.rule_breaker[0]' includes a potentially sensitive attribute which is defined within the project.
.../main.tf:81


      78 |     }
      79 |   }
      80 |
      81 |   automount_service_account_token = "true"    string: "true"
      82 | }
      83 |

  Legacy ID:  GEN003
  Impact:     Block attribute could be leaking secrets
  Resolution: Don't include sensitive data in blocks
```

I think this should be [HIDDEN]. We're not actually passing a secret with this attribute, it's just a boolean.

### Additional contract requirements

- An explicitly configured `automount_service_account_token` on a `kubernetes_service_account` must not trigger the `general-secrets-sensitive-in-attribute` rule.
