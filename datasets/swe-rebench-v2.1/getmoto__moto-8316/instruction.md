moto/core/responses.py `_get_multi_param` bug

> Guidance on **how to reproduce the issue**. Ideally, this should be a
     *small* code sample that can be run immediately by the maintainers.
     Failing that, let us know what you're doing, how often it happens, what
     environment you're using, etc. Be thorough: it prevents us needing to ask
     further questions.

- try to execute this code:
```python
fleet_request = {
        'LaunchTemplateConfigs': [
            {
                'LaunchTemplateSpecification': {
                    'LaunchTemplateName': 'test-template-name',
                    'Version': '$Default'
                },
                'Overrides': [ { "InstanceType": "t3.nano" } ]
            }
        ]
    }
ec2_client.create_fleet(**fleet_request)
```

>  Tell us **what you expected to happen**. When we run your example code,
     what are we expecting to happen? What does "success" look like for your
     code?


https://github.com/getmoto/moto/blob/1b91aee1de3d26902c5e79a3adefb8f391fb9876/moto/ec2/responses/fleets.py#L33
```python
# Expected:
(Pdb) print(launch_template_configs)
[{'LaunchTemplateSpecification': {'LaunchTemplateName': 'test-template-name', 'Version': '$Default'}, 'Overrides': [ {'InstanceType': 't3.nano'} ]}]
```

>   Tell us **what actually happens**. It's not helpful for you to say "it
     doesn't work" or "it fails". Tell us *how* it fails: do you get an
     exception? A hang? How was the actual result different from your expected
     result?

```python
# Actually happens, see Overrides section
(Pdb) print(launch_template_configs)
[{'LaunchTemplateSpecification': {'LaunchTemplateName': 'test-template-name', 'Version': '$Default'}, 'Overrides': [ 't3.nano' ]}]
```

https://github.com/getmoto/moto/blob/1b91aee1de3d26902c5e79a3adefb8f391fb9876/moto/core/responses.py#L701
```python
(Pdb) print(self.querystring)
OrderedDict({'Action': ['CreateFleet'],
 'Version': ['2016-11-15'],
 'Type': ['request'],
 'ValidUntil': ['2024-11-14T08:57:24.289912Z'],
 /* ... cropped ... */
 'LaunchTemplateConfigs.1.LaunchTemplateSpecification.LaunchTemplateName': ['test-template-name'],
 'LaunchTemplateConfigs.1.LaunchTemplateSpecification.Version': ['$Default'],
 'LaunchTemplateConfigs.1.Overrides.1.InstanceType': ['t3.nano']
 /* ... cropped ... */})
```

```python
# how it fails
            launch_template_data = launch_template.latest_version().data
            new_launch_template = launch_template_data.copy()
            if config.get("Overrides"):
                for override in config["Overrides"]:
>                   new_launch_template.update(override)
E                   ValueError: dictionary update sequence element #0 has length 1; 2 is required

.venv/lib/python3.13/site-packages/moto/ec2/models/fleets.py:73: ValueError
```



>  Tell us **what version of Moto you're using**, and
     **how you installed it**. Tell us whether you're using standalone server
     mode or the Python mocks. If you are using the Python mocks, include the
     version of boto/boto3/botocore.

- `5.0.20`
