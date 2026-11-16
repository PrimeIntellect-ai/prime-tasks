implementation_coverage.py script misses covered API calls
I saw that the implementation coverage for KMS reports that some alias methods are not supported:

```
## kms
<details>
<summary>56% implemented</summary>
# ...
- [ ] create_alias
# ...
- [X] delete_alias
# ...
- [ ] list_aliases
# ...
- [ ] update_alias
```

When I checked the actual implementation, those methods all seem to be supported, so I looked into `scripts/implementation_coverage.py`. It appears that the method names on the service backend are used to determine if a given method exists.

```python

from moto.backends import get_backend

# ...

def get_moto_implementation(service_name):
    try:
        backends = get_backend(service_name)
        backend = (
            backends[0]["us-east-1"]
            if "us-east-1" in backends[0]
            else backends[0]["global"]
        )
        return backend, service_name
    except ModuleNotFoundError:
        return None, service_name

def calculate_extended_implementation_coverage():
        # ...
        moto_client, mock_name = get_moto_implementation(service_name)
        if not moto_client:
            continue
        real_client = boto3.client(service_name, region_name="us-east-1")
        implemented = dict()
        not_implemented = []

        operation_names = [
            xform_name(op) for op in real_client.meta.service_model.operation_names
        ]
        # Not part of the spec - but very much part of S3
        if service_name == "s3":
            operation_names.extend(["upload_file", "upload_fileobj"])

        for op in operation_names:
            if moto_client and op in dir(moto_client):
                implemented[op] = getattr(moto_client, op)
            else:
                not_implemented.append(op)
```

In case of KMS the issue is, that the method names on the `KmsBackend` don't match the API names, i.e.:

|**boto3 Name**|**KmsBackend method**|**KmsResponse method**
|---|---|---|
|create_alias|add_alias|create_alias|
|delete_alias|delete_alias|delete_alias|
|list_aliases|get_all_aliases|list_aliases|
|update_alias| - |update_alias|

It seems like the `KmsResponse` is more reliable in this case.

Maybe similar to: https://github.com/getmoto/moto/issues/3599

I'd be willing to try and fix it, but I'm not sure how to proceed...
([HIDDEN], but this may be a more widespread issue)
