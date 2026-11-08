Library usage: write_policy_with_template does not ignore empty lists
The example [here](https://github.com/salesforce/policy_sentry/blob/master/examples/library-usage/writing/write_policy_with_access_levels.py) works as-is, but if you remove any of the access levels, it breaks. The error indicates that this is because it does not ignore empty lists, even though it ignores empty strings.

```python
from policy_sentry.writing.template import get_crud_template_dict
from policy_sentry.command.write_policy import write_policy_with_template
import json


if __name__ == '__main__':
    crud_template = get_crud_template_dict()
    crud_template['read'].append("arn:aws:secretsmanager:us-east-1:123456789012:secret:mysecret")
    crud_template['write'].append("arn:aws:secretsmanager:us-east-1:123456789012:secret:mysecret")
    crud_template['list'].append("arn:aws:s3:::mybucket/stuff")
    # by commenting out the line below, you get an IndexError
    # crud_template['permissions-management'].append("arn:aws:kms:us-east-1:123456789012:key/123456")
    crud_template['tagging'].append("arn:aws:ssm:us-east-1:123456789012:parameter/test")
    wildcard_actions_to_add = ["kms:createcustomkeystore", "cloudhsm:describeclusters"]
    crud_template['wildcard-only']['single-actions'].extend(wildcard_actions_to_add)
    policy = write_policy_with_template(crud_template)
    print(json.dumps(policy, indent=4))
```

Resulting error:

```
Traceback (most recent call last):
  File "./examples/library-usage/writing/write_policy_with_access_levels.py", line 18, in <module>
    policy = write_policy_with_template(crud_template)
  File "./policy_sentry/venv/lib/python3.8/site-packages/policy_sentry/command/write_policy.py", line 77, in write_policy_with_template
    policy = sid_group.process_template(cfg, minimize)
  File "./policy_sentry/venv/lib/python3.8/site-packages/policy_sentry/writing/sid_group.py", line 472, in process_template
    and cfg["permissions-management"][0] != ""
IndexError: list index out of range
```

Fix coming shortly.
