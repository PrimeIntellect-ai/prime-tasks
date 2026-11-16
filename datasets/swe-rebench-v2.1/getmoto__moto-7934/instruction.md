application-autoscalin.put_scheduled_action are incorrectly overwritten
Hi

In moto, `application-autoscalin.put_scheduled_action` only stores one Scheduled action for one combination of `ServiceNamespace`, `ScalableDimension` and `ResourceId`. No such limit is in place for AWS.

**how to reproduce the issue**

Steps are:
1. add two scheduled actions for one combination of `ServiceNamespace`, `ScalableDimension` and `ResourceId`.
2. fetch  scheduled actions for the same combination

Expected result would be that we have two actions but we have one. There's a code snippet below to reproduce.

<details><summary>Code Snippet to recreate issue</summary>

```python
import os

import boto3
import moto


os.environ["AWS_DEFAULT_REGION"] = "us-west-2"


def main() -> None:
    with moto.mock_applicationautoscaling():
        client = boto3.client("application-autoscaling")

        client.put_scheduled_action(
            ServiceNamespace="sagemaker",
            Schedule="cron(0 0 * * * *)",
            ScheduledActionName="scale-at-midnight",
            ResourceId="endpoint/endpoint-name/variant/variant-name",
            ScalableDimension="sagemaker:variant:DesiredInstanceCount",
            ScalableTargetAction={"MinCapacity": 1},
        )
        client.put_scheduled_action(
            ServiceNamespace="sagemaker",
            Schedule="cron(0 30 * * * *)",
            ScheduledActionName="scale-at-half-past-midnight",
            ResourceId="endpoint/endpoint-name/variant/variant-name",
            ScalableDimension="sagemaker:variant:DesiredInstanceCount",
            ScalableTargetAction={"MinCapacity": 2},
        )

        actions = client.describe_scheduled_actions(
            ServiceNamespace="sagemaker",
        )
        print(f"{len(actions)=}")
        print(actions['ScheduledActions'])


if __name__ == '__main__':
    main()

```

</details>

**what you expected to happen**

Multiple actions with the same `ServiceNamespace`, `ScalableDimension` and `ResourceId` to be preserved same as AWS.

**what actually happens**

The last action is stored. From a brief glance at the code, it is likely due to https://github.com/getmoto/moto/blob/master/moto/applicationautoscaling/models.py#L306-L316.

**what version of Moto you're using**

`moto==4.0.10`
