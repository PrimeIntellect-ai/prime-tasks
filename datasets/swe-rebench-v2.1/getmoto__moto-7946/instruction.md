primary Athena workgroup is missing EnforceWorkGroupConfiguration
The primary Athena workgroup initialized [here](https://github.com/getmoto/moto/blob/master/moto/athena/models.py#L181-L183), does not have the `EnforceWorkGroupConfiguration` set. This prevents running `awswrangler.athena.read_sql_query()` against `moto`, resulting in

```
File "... /awswrangler/athena/_utils.py", line 147, in _get_workgroup_config
    enforced = res["WorkGroup"]["Configuration"]["EnforceWorkGroupConfiguration"]
               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
KeyError: 'EnforceWorkGroupConfiguration'
```

I reported this first with `awswrangler` [here](https://github.com/aws/aws-sdk-pandas/issues/2904), and got the following reply

>The [line](https://github.com/aws/aws-sdk-pandas/blob/ae4a4e391eaacc00bc661eabc35cf6f91e84e560/awswrangler/athena/_utils.py#L146) you are referencing is using the Athena [get_workgroup](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/athena/client/get_work_group.html) boto3 API under the hood to pull the workgroup information. In the response, the EnforceWorkGroupConfiguration boolean is always returned.

>I agree that the enforce configuration is optional when creating a workgroup, but it is always available when getting it (i.e. a default is set if none is provided). So I would argue that the issue here lies with moto which is not creating/referencing the workgroup correctly

I currently work around this by creating my own `moto` Docker image like this:
```
FROM motoserver/moto:latest

[HIDDEN]

```

### Additional contract requirements

- The `Configuration` returned for the primary workgroup must include the `EnforceWorkGroupConfiguration` key.
