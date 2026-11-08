CICD Multi Account or Multi Region Deployment Fails
### Describe the bug

When trying to deploy multi env, multi account or multi region cicd pipelines using CICDPipelineStack, the cdk synth fails at pipeline.synth() step with the error _"RuntimeError: Error: Pipeline stack which uses cross-environment actions must have an explicitly set region"_.

### How to Reproduce

```
pipeline = CICDPipelineStack(
    app,
    id=pipeline_name,
    environment_id="cicd",
    pipeline_name=pipeline_name,
    env=cdk.Environment(
        account=cicd_params.get_config_attribute("account"),
        region=cicd_params.get_config_attribute("region"),
    ),
)
pipeline.add_source_action(repository_name=repository_name)
pipeline.add_synth_action()
pipeline.build_pipeline() # type:ignore
pipeline.add_stage(
    stage_id="dev-storage",
    stage=DataStorageStage(
    app,
    env=cdk.Environment(
        account=storage_params.get_config_attribute("account"),
        region=storage_params.get_config_attribute("region"),
    ),
    environment_id="stor",
    mode=mode,
    compute_params=compute_params,

),
)
pipeline.add_stage(
    stage_id="dev-compute",
    stage=DataComputeStage(
    app,
    environment_id="comp",
    mode=mode,
    storage_params=storage_params,
    env=cdk.Environment(
        account=compute_params.get_config_attribute("account"),
        region=compute_params.get_config_attribute("region"),
    ),
),
)

pipeline.synth()
#######################

app.synth()

```

If you use the cross account cross region pipeline example with the above code changes and then run cdk synth you can go to cdk.out and check the assembly-comp and assembly stor manifest.json will take in the correct region and account from ddk.json, likewise if you check the manifest.json for the pipeline, you will see that even though we pass environment it will be unknown, [HIDDEN]

### Expected behavior

It should synthesize correctly with supplied env (account and region)

### Your project

_No response_

### Screenshots

_No response_

### Environment

```
Provide your `pip list` output, particularly the version of the AWS DDK library you used. Providing this information may significantly improve resolution times.
```


### OS

Mac

### Python version

3.9

### AWS DDK version

1.0.0b

### Additional context

_No response_

### Additional contract requirements

- When a `CICDPipelineStack` is created with an `env` that supplies both an `account` and a `region`, the synthesized stack must use those supplied values: the stack's `account` equals the supplied account and its `region` equals the supplied region.
- A `CICDPipelineStack` with a supplied environment must synthesize successfully when its pipeline contains cross-environment stages.
- `BaseStack` must honour the standard CDK stack options passed through its props, including `description` and `stackName`.
