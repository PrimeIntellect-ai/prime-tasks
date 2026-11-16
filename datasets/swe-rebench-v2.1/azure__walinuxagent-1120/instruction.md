Exception retrieving artifacts profile: TypeError: decoding str is not supported
I am tracking a annoying issue in the BVTs with the following signature.

```text
Exception retrieving artifacts profile: TypeError: decoding str is not supported
```

I increased debugging, and found this call stack.

```text
2018/04/18 06:03:51.919139 WARNING Exception retrieving artifacts profile: Traceback (most recent call last):
  File "/usr/local/lib/python3.5/dist-packages/azurelinuxagent/common/protocol/wire.py", line 1135, in get_artifacts_profile
    profile = self.decode_config(config)
  File "/usr/local/lib/python3.5/dist-packages/azurelinuxagent/common/protocol/wire.py", line 563, in decode_config
    xml_text = ustr(data, encoding='utf-8')
TypeError: decoding str is not supported
```

[HIDDEN]

The method decode_config is confusing because it has variables like xml_text, but the data passed in this case is actually JSON.  Azure does not do us any favors because some systems return XML and other returns JSON.  The agent could or should be smarter about this.

The bug was introduced with d0b583cc.

### Additional contract requirements

Artifact-profile retrieval must accept a JSON response body provided as text and return the parsed profile without raising the reported decoding `TypeError`.
