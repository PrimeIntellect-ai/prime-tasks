Attempting to remove an item from a dynamodb list along with another attribute throws a TypeError when using an UpdateExpression
# Bug Report

Python Version: 3.12.3
Moto version: 5.0.14
Moto extras: moto = dynamodb, dynamodbstreams

Installed using poetry in a virtual environment

When attempting to remove an item from a dynamodb list as well as removing another attribute at the same time, a TypeError is thrown due to the inability to compare a numeric index value with an attribute name.

## Sample Code

```python3.12
import boto3
from moto import mock_aws

TABLE_NAME = "MyTestTable"

mx = mock_aws()
mx.start()

payload = {
    "PK": {"S": "primary_key"},
    "SK": {"S": "sort_key"},
    "current_user": {
        "M": {
            "name": {"S": "John"},
            "surname": {"S": "Doe"}
        }
    },
    "user_list": {"L": [{"M": {
        "name": {"S": "John"},
        "surname": {"S": "Doe"}
    }},
        {"M": {
            "name": {"S": "Jane"},
            "surname": {"S": "Smith"}
        }},
        {"M": {
            "name": {"S": "John"},
            "surname": {"S": "Smith"}
        }}]
    },
    "some_param": {
        "NULL": True
    }
}

expected = {
    "PK": {"S": "primary_key"},
    "SK": {"S": "sort_key"},
    "current_user": {"M": {
        "name": {"S": "Jane"},
        "surname": {"S": "Smith"}
    }},
    "user_list": {
        "L": [{"M": {
            "name": {"S": "Jane"},
            "surname": {"S": "Smith"}
        }},
            {"M": {
                "name": {"S": "John"},
                "surname": {"S": "Smith"}
            }}]
    }
}


def test_ddb_update_item(ddb_client):
    ddb_client.create_table(
        TableName=TABLE_NAME,
        AttributeDefinitions=[
            {
                'AttributeName': 'PK',
                'AttributeType': 'S'
            },
            {
                'AttributeName': 'SK',
                'AttributeType': 'S'
            }
        ],
        KeySchema=[
            {
                'AttributeName': 'PK',
                'KeyType': 'HASH'
            },
            {
                'AttributeName': 'SK',
                'KeyType': 'RANGE'
            }
        ],
        BillingMode='PAY_PER_REQUEST',
    )
    ddb_client.put_item(
        TableName=TABLE_NAME,
        Item=payload
    )
    ddb_client.update_item(
        TableName=TABLE_NAME,
        Key={
            "PK": {"S": "primary_key"},
            "SK": {"S": "sort_key"}

        },
        UpdateExpression="REMOVE #ulist[0], some_param SET current_user = :current_user",
        ExpressionAttributeNames={
            "#ulist": "user_list",
        },
        ExpressionAttributeValues={
            ":current_user": {"M": {
                "name": {"S": "Jane"},
                "surname": {"S": "Smith"}
            }}
        }
    )


    result = ddb_client.get_item(
        TableName=TABLE_NAME,
        Key={
            "PK": {"S": "primary_key"},
            "SK": {"S": "sort_key"}
        })
    assert result['Item'] == expected

client = boto3.client('dynamodb')
test_ddb_update_item(client)


```

## Traceback:

```
Traceback (most recent call last):
  File "/home/user/Documents/ddb-bug/scripts/runme.py", line 114, in <module>
    test_ddb_update_item(client)
  File "/home/user/Documents/ddb-bug/scripts/runme.py", line 85, in test_ddb_update_item
    ddb_client.update_item(
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/client.py", line 514, in _api_call
    return self._make_api_call(operation_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/client.py", line 921, in _make_api_call
    http, parsed_response = self._make_request(
                            ^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/client.py", line 944, in _make_request
    return self._endpoint.make_request(operation_model, request_dict)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/endpoint.py", line 119, in make_request
    return self._send_request(request_dict, operation_model)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/endpoint.py", line 202, in _send_request
    while self._needs_retry(
          ^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/endpoint.py", line 354, in _needs_retry
    responses = self._event_emitter.emit(
                ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 412, in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 256, in emit
    return self._emit(event_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 239, in _emit
    response = handler(**kwargs)
               ^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 207, in __call__
    if self._checker(**checker_kwargs):
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 284, in __call__
    should_retry = self._should_retry(
                   ^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 307, in _should_retry
    return self._checker(
           ^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 363, in __call__
    checker_response = checker(
                       ^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 247, in __call__
    return self._check_caught_exception(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/retryhandler.py", line 416, in _check_caught_exception
    raise caught_exception
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/endpoint.py", line 278, in _do_get_response
    responses = self._event_emitter.emit(event_name, request=request)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 412, in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 256, in emit
    return self._emit(event_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/botocore/hooks.py", line 239, in _emit
    response = handler(**kwargs)
               ^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/core/botocore_stubber.py", line 38, in __call__
    response = self.process_request(request)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/core/botocore_stubber.py", line 88, in process_request
    status, headers, body = method_to_execute(
                            ^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/core/responses.py", line 291, in dispatch
    return cls()._dispatch(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/core/responses.py", line 503, in _dispatch
    return self.call_action()
           ^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/utilities/aws_headers.py", line 44, in _wrapper
    response = f(*args, **kwargs)
               ^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/dynamodb/responses.py", line 194, in call_action
    return super().call_action()
           ^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/core/responses.py", line 591, in call_action
    response = method()
               ^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/dynamodb/responses.py", line 933, in update_item
    item = self.dynamodb_backend.update_item(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/dynamodb/models/__init__.py", line 521, in update_item
    validated_ast.normalize()
  File "/home/user/.pyenv/versions/3.12.3/envs/ddb-bug-3.12/lib/python3.12/site-packages/moto/dynamodb/parsing/ast_nodes.py", line 79, in normalize
    sorted_actions.extend(sorted(remove_actions, reverse=True))
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  [HIDDEN]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: '<' not supported between instances of 'int' and 'str'
```

the issue can be avoided by adding another REMOVE tag at the end of the update expression like below:
```
UpdateExpression="REMOVE #ulist[0] SET current_user = :current_user REMOVE some_param"
```

However this is an invalid UpdateExpression when run on AWS. (another separate bug on moto)

### Additional contract requirements

- An UpdateExpression that removes a list element and another attribute in the same REMOVE clause while setting another attribute must complete without a TypeError and apply all requested changes to the item.
