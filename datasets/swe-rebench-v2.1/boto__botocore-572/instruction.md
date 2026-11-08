route53 client list_resource_record_sets fails with StartRecordType
**OS:** OS X Yosemite
**Python:** 2.7.6
**botocore:** 0.106.0

I'm trying to get the SOA records on a route53 hosted zone.  When I try to do so, it fails badly - I get the following response:

```python
{'ResponseMetadata': {'HTTPStatusCode': 400, 'RequestId': '24865775-f4fb-11e4-a914-45b54a9f75e8'}, 'Error': {'Code': 'InvalidInput', 'Type': 'Sender'}}
```

This is further exacerbated in `exceptions.ClientError.__init__` when it looks for ['Error']['Message'] which doesn't exist in the InvalidInput error.

Here's the code I'm using:

```python
>>> from boto3.session import Session
>>> sess = Session(region_name='us-east-1')
>>> r53 = sess.client('route53')
>>> zone = r53.list_hosted_zones_by_name(DNSName='example.com.')['HostedZones'][0]
>>> zid = zone['Id']
>>> r53.list_resource_record_sets(HostedZoneId=zid, StartRecordType='SOA')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/mike/venv/stacker/lib/python2.7/site-packages/botocore-0.106.0-py2.7.egg/botocore/client.py", line 199, in _api_call
    return self._make_api_call(operation_name, kwargs)
  File "/Users/mike/venv/stacker/lib/python2.7/site-packages/botocore-0.106.0-py2.7.egg/botocore/client.py", line 254, in _make_api_call
    raise ClientError(parsed_response, operation_name)
  File "/Users/mike/venv/stacker/lib/python2.7/site-packages/botocore-0.106.0-py2.7.egg/botocore/exceptions.py", line 300, in __init__
    error_message=error_response['Error']['Message'],
KeyError: 'Message'
```
