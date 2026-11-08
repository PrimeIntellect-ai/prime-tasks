Can't create a client when using Cross-account role (datetime.datetime' object has no attribute 'read')
Get an 'AttributeError: 'datetime.datetime' object has no attribute 'read'' exception when creating a client using a Cross-Account role:

```
import botocore.session

session = botocore.session.get_session()
client = session.create_client('ec2')
```

```
Traceback (most recent call last):
  File "test_botocore.py", line 4, in <module>
    client = session.create_client('ec2',region_name='ap-southeast-2')
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/session.py", line 788, in create_client
    credentials = self.get_credentials()
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/session.py", line 434, in get_credentials
    'credential_provider').load_credentials()
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/credentials.py", line 869, in load_credentials
    creds = provider.load()
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/credentials.py", line 637, in load
    return self._load_creds_via_assume_role()
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/credentials.py", line 656, in _load_creds_via_assume_role
    creds, response = self._retrieve_temp_credentials()
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/credentials.py", line 765, in _retrieve_temp_credentials
    creds = self._create_creds_from_response(response)
  File "/usr/local/lib/python2.7/dist-packages/botocore-1.3.15-py2.7.egg/botocore/credentials.py", line 742, in _create_creds_from_response
    [HIDDEN]
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 1008, in parse
    return DEFAULTPARSER.parse(timestr, **kwargs)
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 392, in parse
    res = self._parse(timestr, **kwargs)
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 492, in _parse
    l = _timelex.split(timestr)         # Splits the timestr into tokens
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 174, in split
    return list(cls(s))
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 171, in next
    return self.__next__()  # Python 2.x support
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 164, in __next__
    token = self.get_token()
  File "/usr/local/lib/python2.7/dist-packages/dateutil/parser.py", line 82, in get_token
    nextchar = self.instream.read(1)
AttributeError: 'datetime.datetime' object has no attribute 'read'
```

My credentials file (which works perfectly using the CLI) looks like this:

```
[Master]
aws_access_key_id = XXXXXXXXXXXXXX
aws_secret_access_key = YYYYYYYYYYYYYYYYYYY

[Test]
role_arn = arn:aws:iam::zzzzzzzzzzzz:role/MyRoleOnMaster
source_profile = Master
```

Using the Master profile works ok, the problem is using the Test profile.

Python 2.7.6
Botocore 1.3.15

### Additional contract requirements

- When an STS response for an assumed role provides its expiration as a `datetime.datetime` value, credential loading must complete without the reported parser error so a client can be created with the cross-account role.
