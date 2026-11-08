update_autoscaling_group returns KeyError instead of ValidationError when ASG name is not found
Hello,

I'm using moto to test a function that updates an autoscaling group. The tests for successful autoscaling group update works as expected. The error produced when an invalid autoscaling group name is provided, is not as expected.

I expect a `botocore.exceptions.ClientError.ValidationError` when providing an invalid autoscaling group name. Example error.response expected:
```
{'Error': {'Type': 'Sender', 'Code': 'ValidationError', 'Message': 'AutoScalingGroup name not found - null'}, 'ResponseMetadata': {'RequestId': '<redacted>', 'HTTPStatusCode': 400, 'HTTPHeaders': {'x-amzn-requestid': '<redacted>', 'content-type': 'text/xml', 'content-length': '292', 'date': 'Wed, 14 Aug 2024 23:25:56 GMT', 'connection': 'close'}, 'RetryAttempts': 0}}
```

Instead moto throws a `KeyError`.

Traceback:
```
pytest test/test.py
============================================= test session starts ==============================================
platform darwin -- Python 3.12.3, pytest-8.3.2, pluggy-1.5.0
rootdir: <redacted>
collected 23 items

test/test.py ....F..................                                         [100%]

=================================================== FAILURES ===================================================
______________________________________________ test_scale_asg_dne ______________________________________________

aws_session = Session(region_name='us-east-1')

    def test_scale_asg_dne(aws_session):
        client = aws_session.client("autoscaling")
        try:
>           client.update_auto_scaling_group(
                AutoScalingGroupName="fake-asg",
                MinSize=2,
                MaxSize=2,
                DesiredCapacity=2,
            )

test/test.py:151:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
lib/python3.12/site-packages/botocore/client.py:565: in _api_call
    return self._make_api_call(operation_name, kwargs)
lib/python3.12/site-packages/botocore/client.py:999: in _make_api_call
    http, parsed_response = self._make_request(
lib/python3.12/site-packages/botocore/client.py:1023: in _make_request
    return self._endpoint.make_request(operation_model, request_dict)
lib/python3.12/site-packages/botocore/endpoint.py:119: in make_request
    return self._send_request(request_dict, operation_model)
lib/python3.12/site-packages/botocore/endpoint.py:200: in _send_request
    while self._needs_retry(
lib/python3.12/site-packages/botocore/endpoint.py:352: in _needs_retry
    responses = self._event_emitter.emit(
lib/python3.12/site-packages/botocore/hooks.py:412: in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
lib/python3.12/site-packages/botocore/hooks.py:256: in emit
    return self._emit(event_name, kwargs)
lib/python3.12/site-packages/botocore/hooks.py:239: in _emit
    response = handler(**kwargs)
lib/python3.12/site-packages/botocore/retryhandler.py:207: in __call__
    if self._checker(**checker_kwargs):
lib/python3.12/site-packages/botocore/retryhandler.py:284: in __call__
    should_retry = self._should_retry(
lib/python3.12/site-packages/botocore/retryhandler.py:307: in _should_retry
    return self._checker(
lib/python3.12/site-packages/botocore/retryhandler.py:363: in __call__
    checker_response = checker(
lib/python3.12/site-packages/botocore/retryhandler.py:247: in __call__
    return self._check_caught_exception(
lib/python3.12/site-packages/botocore/retryhandler.py:416: in _check_caught_exception
    raise caught_exception
lib/python3.12/site-packages/botocore/endpoint.py:276: in _do_get_response
    responses = self._event_emitter.emit(event_name, request=request)
lib/python3.12/site-packages/botocore/hooks.py:412: in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
lib/python3.12/site-packages/botocore/hooks.py:256: in emit
    return self._emit(event_name, kwargs)
lib/python3.12/site-packages/botocore/hooks.py:239: in _emit
    response = handler(**kwargs)
lib/python3.12/site-packages/moto/core/botocore_stubber.py:37: in __call__
    response = self.process_request(request)
lib/python3.12/site-packages/moto/core/botocore_stubber.py:84: in process_request
    status, headers, body = method_to_execute(
lib/python3.12/site-packages/moto/core/responses.py:290: in dispatch
    return cls()._dispatch(*args, **kwargs)
lib/python3.12/site-packages/moto/core/responses.py:501: in _dispatch
    return self.call_action()
lib/python3.12/site-packages/moto/utilities/aws_headers.py:44: in _wrapper
    response = f(*args, **kwargs)
lib/python3.12/site-packages/moto/autoscaling/responses.py:19: in call_action
    return super().call_action()
lib/python3.12/site-packages/moto/core/responses.py:587: in call_action
    response = method()
lib/python3.12/site-packages/moto/autoscaling/responses.py:251: in update_auto_scaling_group
    self.autoscaling_backend.update_auto_scaling_group(
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <moto.autoscaling.models.AutoScalingBackend object at 0x105cf3500>, name = 'fake-asg'
availability_zones = [], desired_capacity = 2, max_size = 2, min_size = 2, launch_config_name = None
launch_template = {}, vpc_zone_identifier = None, health_check_period = None, health_check_type = None
new_instances_protected_from_scale_in = None

    def update_auto_scaling_group(
        self,
        name: str,
        availability_zones: List[str],
        desired_capacity: Optional[int],
        max_size: Optional[int],
        min_size: Optional[int],
        launch_config_name: str,
        launch_template: Dict[str, Any],
        vpc_zone_identifier: str,
        health_check_period: int,
        health_check_type: str,
        new_instances_protected_from_scale_in: Optional[bool] = None,
    ) -> FakeAutoScalingGroup:
        """
        The parameter DefaultCooldown, PlacementGroup, TerminationPolicies are not yet implemented
        """
        # TODO: Add MixedInstancesPolicy once implemented.
        # Verify only a single launch config-like parameter is provided.
        if launch_config_name and launch_template:
            raise ValidationError(
                "Valid requests must contain either LaunchTemplate, LaunchConfigurationName "
                "or MixedInstancesPolicy parameter."
            )

>       [HIDDEN]
E       KeyError: 'fake-asg'

lib/python3.12/site-packages/moto/autoscaling/models.py:1175: KeyError
```

Reproducing issue, run `pytest test.py`:
```
# test.py
import boto3
import botocore
import pytest
from moto import mock_aws

@pytest.fixture(scope="function")
def aws_credentials():
    """Mocked AWS Credentials"""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"

@pytest.fixture(scope="function")
def aws_session(aws_credentials):
    """Mocked AWS Session"""
    with mock_aws():
        yield boto3.Session(aws_credentials)

def test_scale_asg_dne(aws_session):
    client = aws_session.client("autoscaling")
    try:
        client.update_auto_scaling_group(
            AutoScalingGroupName="fake-asg",
            MinSize=2,
            MaxSize=2,
            DesiredCapacity=2,
        )
   # throws a KeyError instead of ValidationError
    except botocore.exceptions.ClientError as err:
      if err.response["Error"]["Code"] == "ValidationError":
        print("A validation error occurred")
```

Environment details:
 - moto==5.0.12 installed with pip
 - using mocks. boto3==1.34.155, botocore==1.34.155
 - pytest==8.3.2
 - Python 3.12.3

Thank you!
