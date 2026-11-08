Crash in authorization  'NoneType' object has no attribute 'startswith'
When reaching `/v1/__user_data__`

```
AttributeError: 'NoneType' object has no attribute 'startswith'
(6 additional frame(s) were not displayed)
...
  File "pyramid/config/views.py", line 214, in predicate_wrapper
    return view(context, request)
  File "pyramid/viewderivers.py", line 323, in secured_view
    result = permitted(context, request)
  File "pyramid/viewderivers.py", line 320, in permitted
    return authz_policy.permits(context, principals, permission)
  File "kinto/core/authorization.py", line 72, in permits
    allowed = context.check_permission(principals, bound_perms)
  File "kinto/core/authorization.py", line 189, in check_permission
    if self.resource_name and permission.startswith(self.resource_name):
```
