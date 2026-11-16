Lambda update_function_code not incrementing Version when Publish=True
When running the following beneath moto
```python
import boto3
client = boto3.client('lambda', region_name='us-east-2')
res = client.update_function_code(FunctionName='test-function', ZipFile=<somearchive>, Publish=True)
print(res["Version"])
```
After the first invocation this prints out `1`, but this also prints out  `1` for both results if the following is run:
```python
import boto3
client = boto3.client('lambda', region_name='us-east-2')
res = client.update_function_code(FunctionName='test-function', ZipFile=<somearchive>, Publish=True)
print(res["Version"])
res = client.update_function_code(FunctionName='test-function', ZipFile=<somearchive>, Publish=True)
print(res["Version"])
```
I would expect the second invocation to print out `2` since a new version is getting published.
