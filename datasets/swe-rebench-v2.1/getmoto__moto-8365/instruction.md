KMS get_public_key fails with alias
Hi,

The following test, trying to use `get_public_key` with an alias is failing:

```python
import boto3
from moto import mock_aws

@mock_aws
def test():
    kms = boto3.client("kms", region_name="eu-west-1")
    key = kms.create_key(
        KeyUsage="SIGN_VERIFY",
        KeySpec="ECC_NIST_P256",
    )
    key_id = key["KeyMetadata"]["KeyId"]
    kms.create_alias(
        AliasName="alias/foo",
        TargetKeyId=key_id,
    )
    kms.get_public_key(KeyId="alias/foo")
```
raises the following exception:
```
/Users/xxx/Library/Caches/pypoetry/virtualenvs/motoreport-c38uzrXm-py3.11/bin/python /Users/xxx/PycharmProjects/cebidhem/motoReport/report/main.py
Traceback (most recent call last):
  File "/Users/xxx/PycharmProjects/cebidhem/motoReport/report/main.py", line 18, in main
    kms.get_public_key(KeyId="alias/foo")
  File "/Users/xxx/Library/Caches/pypoetry/virtualenvs/motoreport-c38uzrXm-py3.11/lib/python3.11/site-packages/botocore/client.py", line 569, in _api_call
    return self._make_api_call(operation_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/xxx/Library/Caches/pypoetry/virtualenvs/motoreport-c38uzrXm-py3.11/lib/python3.11/site-packages/botocore/client.py", line 1023, in _make_api_call
    raise error_class(parsed_response, operation_name)
botocore.errorfactory.NotFoundException: An error occurred (NotFoundException) when calling the GetPublicKey operation: Invalid keyId alias/foo
```

Somehow, the alias isn't recognized as an alias or it doesn't get translated as the actual keyId.

The only place where I can find the error `Invalid keyId ` is in the `_validate_cmk_id(self, key_id: str)`, which seems weird considering I try to use an alias.

I'm using:
- Python 3.11.1
- moto 5.0.22
- boto3 1.35.75

I can also confirm that it works normally outside of moto with real AWS calls.
