No ValidationException raised when calling DDB UpdateItem operation with an empty ExpressionAttributeValues
If you pass a blank ExpressionAttributeValues parameter to the DDB update_item it should raise a ValidationException. With moto the code executes and the update is performed successfully.

The following
```python
        updateExpression = "REMOVE #records.#key"
        expressionAttributeNames = {"#records": "Records", "#key": key}
        expressionAttributeValues = {}
        itemkeys = self.keygen({"Name": lookup_name}, "Lookup#")
        self.table.update_item(
            Key={"key": itemkeys["key"], "sort": itemkeys["sort"]},
            UpdateExpression=updateExpression,
            ExpressionAttributeNames=expressionAttributeNames,
            ExpressionAttributeValues=expressionAttributeValues,
        )
```

produces

```shell
  File "... /nc_ddb.py", line 127, in DDBupdate_item
    return self.table.update_item(**kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/rodos/.pyenv/versions/3.12.2/lib/python3.12/site-packages/boto3/resources/factory.py", line 581, in do_action
    response = action(self, *args, **kwargs)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/rodos/.pyenv/versions/3.12.2/lib/python3.12/site-packages/boto3/resources/action.py", line 88, in __call__
    response = getattr(parent.meta.client, operation_name)(*args, **params)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/rodos/.pyenv/versions/3.12.2/lib/python3.12/site-packages/botocore/client.py", line 565, in _api_call
    return self._make_api_call(operation_name, kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/rodos/.pyenv/versions/3.12.2/lib/python3.12/site-packages/botocore/client.py", line 1021, in _make_api_call
    raise error_class(parsed_response, operation_name)
botocore.exceptions.ClientError: An error occurred (ValidationException) when calling the UpdateItem operation: ExpressionAttributeValues must not be empty
```

This is when using mocks and with latest version
```shell
source % pip freeze | grep -i 'moto\|boto3'
boto3==1.34.157
moto==5.0.12
```

Its a small thing but when doing TDD my tests did not pick this up and the error did not occur until I started using this against the DynamoDB local instance. I assume the same error is produced against the DDB service given the local instance does it.

Great library, Moto is really just fantastic!
