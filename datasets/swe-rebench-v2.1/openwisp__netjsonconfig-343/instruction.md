error on netjsonconfig: 1.1.1.post1 convert config.tar.gz to json for zerotier
Hi,
I tried uploading the original zerotier config to my router without changing anything.
I saved the backup and ran the conversion instructions.

`netjsonconfig --native config.tar.gz --backend openwrt --method json -a indent="    "`

I get this error:
```
$ netjsonconfig --native backup-ReginaMargherita116-AP-2025-02-26.tar.gz --backend openwrt --method json -a indent="    "
Traceback (most recent call last):
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/base/backend.py", line 157, in validate
    Draft4Validator(self.schema, format_checker=draft4_format_checker).validate(
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/jsonschema/validators.py", line 451, in validate
    raise error
jsonschema.exceptions.ValidationError: '0' is not of type 'boolean'

Failed validating 'type' in schema['properties']['zerotier']['items']['properties']['networks']['items']['properties']['allow_global']:
    OrderedDict([('type', 'boolean'),
                 ('title', 'Allow Global'),
                 ('default', False),
                 ('format', 'checkbox'),
                 ('description',
                  'Allow ZeroTier to set Global/Public/Not-Private range '
                  'IPs and Routes')])

On instance['zerotier'][0]['networks'][0]['allow_global']:
    '0'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/home/michele/.local/bin/netjsonconfig", line 174, in <module>
    instance = backend_class(**options)
               ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/openwrt/openwrt.py", line 56, in __init__
    super().__init__(config, native, templates, context)
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/base/backend.py", line 51, in __init__
    self.parse(native)
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/base/backend.py", line 329, in parse
    self.to_netjson()
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/base/backend.py", line 348, in to_netjson
    self.validate()
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/openwrt/openwrt.py", line 60, in validate
    super().validate()
  File "/home/michele/.local/pipx/venvs/netjsonconfig/lib/python3.11/site-packages/netjsonconfig/backends/base/backend.py", line 161, in validate
    raise ValidationError(e)
netjsonconfig.exceptions.ValidationError: ValidationError '0' is not of type 'boolean'

Failed validating 'type' in schema['properties']['zerotier']['items']['properties']['networks']['items']['properties']['allow_global']:
    OrderedDict([('type', 'boolean'),
                 ('title', 'Allow Global'),
                 ('default', False),
                 ('format', 'checkbox'),
                 ('description',
                  'Allow ZeroTier to set Global/Public/Not-Private range '
                  'IPs and Routes')])

On instance['zerotier'][0]['networks'][0]['allow_global']:
    '0'

```
What am I doing wrong?

I have a need to have a template for the new version of zerotier.
Openwisp even though it has been updated continues to generate the old format.

### Additional contract requirements

- Use the ZeroTier option names `allow_global`, `allow_default`, and `allow_dns` instead of the legacy `allowed_global`, `allowed_default`, and `allowed_dns` names in OpenWrt configuration and its generated NetJSON.
- Represent these options as booleans in NetJSON; convert OpenWrt UCI values `'0'` and `'1'` to `false` and `true`, respectively.
