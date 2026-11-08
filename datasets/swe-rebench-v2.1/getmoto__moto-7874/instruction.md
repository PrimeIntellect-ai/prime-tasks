EventBridge Scheduler get_schedule does not include ActionAfterCompletion in response
**Software versions**

moto version: 5.0.9
boto3 version: 1.34.130
Python version: 3.11.7

**Problem description**

When using the [boto3 EventBridgeScheduler client.get_schedule](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/scheduler/client/get_schedule.html) method, the response received when using moto for mocking purposes does not include `ActionAfterCompletion` in the response.

**Expected behaviour**

moto's implementation of [boto3 EventBridgeScheduler client.get_schedule](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/scheduler/client/get_schedule.html) method should match the response syntax documented by boto3.

**How to reproduce**

Execute the following code:

```python
#!/usr/bin/env python3

import json
from datetime import datetime

import boto3
import moto

if __name__ == "__main__":

    with moto.mock_aws():

        client = boto3.client("scheduler", region_name="us-east-1")
        client.create_schedule(
            FlexibleTimeWindow={"Mode": "OFF"},
            Name="foo",
            ScheduleExpression="cron(1 0 * * *)",
            StartDate=datetime(2024, 6, 19),
            EndDate=datetime(2024, 6, 26),
            ActionAfterCompletion="DELETE",
            Target={
                "Arn": "arn",
                "Input": json.dumps({"x": True}),
                "RoleArn": "role",
            }
        )

        response = client.get_schedule(Name="foo")
        assert "ActionAfterCompletion" in response
```
