elbv2 register_targets returning 200 when registering a stopped instance
From boto3 docs:
> If the target is an EC2 instance, it must be in the running state when you register it.

Reproduce:
- Create an ec2 instance in moto
- Stop that instance
- Create a target group and register that instance in the target group, moto returns 200
  - Expectation: ClientError (InvalidTargetError) is raised

```python
EXAMPLE_AMI_ID = "ami-12c6146b"
pytest.aws_region = "us-west-2"

def test_tg_registration(elbv2):
    from boto3 import client, resource
    import os

    ec2_client = client("ec2")
    ec2_resource = resource("ec2")
    ec2_client.stop_instances(InstanceIds=[elbv2[0]])

    print(elbv2[0])

    res = ec2_resource.instances.filter(Filters=[{"Name": "instance-id", "Values": [elbv2[0]]}])
    for instance in res:
        print(instance.state)
    elb_client = client("elbv2")
    tg_res = elb_client.create_target_group(
            Name="test",
            Protocol="HTTP",
            Port=80,
            VpcId=os.environ["VPC_ID"],
            HealthCheckEnabled=True,
            HealthCheckProtocol="HTTP",
            HealthCheckPort=str(80),
            TargetType="instance",
        )
    print(tg_res["TargetGroups"][0]["TargetGroupArn"])
    target_reg_res = elb_client.register_targets(TargetGroupArn=tg_arn, Targets=targets)
    print(target_reg_res)

@pytest.fixture(scope="session")
def aws_credentials():
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-west-2"
    os.environ["LOG_LEVEL"] = "debug"

@pytest.fixture(scope="session", autouse=True)
def ec2(aws_credentials):
    with mock_aws():
        client = boto3.client("ec2", region_name=pytest.aws_region)
        reservation = client.run_instances(ImageId=EXAMPLE_AMI_ID, MinCount=1, MaxCount=1)
        instance = reservation["Instances"][0]
        instance_id = instance["InstanceId"]
        private_ip_address = instance["PrivateIpAddress"]
        vpc = client.create_vpc(CidrBlock="10.0.0.0/16")
        subnet = client.create_subnet(VpcId=vpc["Vpc"]["VpcId"], CidrBlock="10.0.0.0/18")
        subnet_id = subnet["Subnet"]["SubnetId"]
        os.environ["VPC_ID"] = vpc["Vpc"]["VpcId"]
        logger.info(">>> VPC ID: %s", vpc["Vpc"]["VpcId"])
        logger.info(">>> Subnet ID: %s", subnet["Subnet"]["SubnetId"])
        yield client, instance_id, subnet_id, private_ip_address

@pytest.fixture(scope="session", autouse=True)
def elbv2(ec2):
    with mock_aws():
        client = boto3.client("elbv2", region_name=pytest.aws_region)
        lb = client.create_load_balancer(Name="app-lb", Subnets=[ec2[2]])
        lb_arn = lb["LoadBalancers"][0]["LoadBalancerArn"]

        listener = client.create_listener(
            LoadBalancerArn=lb_arn,
            Protocol="HTTP",
            Port=80,
            DefaultActions=[
                {
                    "Type": "fixed-response",
                    "FixedResponseConfig": {
                        "MessageBody": "test",
                        "StatusCode": "200",
                        "ContentType": "text/plain",
                    },
                }
            ],
        )
        listener_arn = listener["Listeners"][0]["ListenerArn"]
        os.environ["LB_ARN"] = lb_arn
        os.environ["LISTENER_ARN"] = listener_arn

        yield ec2[1], lb_arn, listener_arn
```

Outputs:
```
LISTENER_ARN: arn:aws:elasticloadbalancing:us-west-2:123456789012:listener/app/app-lb/50dc6c495c0c9188/804761638992
{'Code': 80, 'Name': 'stopped'}
arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/test/50dc6c495c0c9188
Target Registration Result: {'ResponseMetadata': {'RequestId': 'dbtP5ZFm6zIoVvxNN8VJi38KivH0HbJYuWeVZpLlWLaZPzasvAIW', 'HTTPStatusCode': 200, 'HTTPHeaders': {'server': 'amazon.com', 'date': 'Sun, 03 Nov 2024 23:57:00 GMT', 'x-amzn-requestid': 'dbtP5ZFm6zIoVvxNN8VJi38KivH0HbJYuWeVZpLlWLaZPzasvAIW'}, 'RetryAttempts': 0}}
```

### Additional contract requirements

- The raised error has the error code `InvalidTarget`.
