API Gateway: query ignored in get_api_keys
As stated in the `get_api_keys` [documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/apigateway/client/get_api_keys.html#APIGateway.Client.get_api_keys), the parameter `nameQuery` is used to filter API Keys by name.

Moto is completely ignoring the query and returning all the keys independently of value passed.

In the following example, the second assert fails because all keys are returned when only the second should match the nameQuery.

Even if `nameQuery` does not guarantee an exact match, Moto should have a similar behavior to AWS.

```python
import boto3
import pytest
from moto import mock_aws


@pytest.fixture()
def api_gateway_mock():
    with mock_aws():
        ag_client = boto3.client("apigateway")

        ag_client.create_api_key(
            name="123-456",
            description="Mock API key 123-456",
            enabled=True,
            tags={"user": "123"},
        )

        ag_client.create_api_key(
            name="654-321",
            description="Mock API key 654-321",
            enabled=True,
            tags={"user": "654"},
        )

        yield ag_client


def test_get_api_keys(api_gateway_mock):
    all_keys = api_gateway_mock.get_api_keys(limit=10).get("items", [])
    assert len(all_keys) == 2
    key_123 = api_gateway_mock.get_api_keys(nameQuery="123-456", limit=10).get("items", [])
    assert len(key_123) == 1
```

Moto version: 5.0.15

`get_api_keys` is marked as implemented in https://docs.getmoto.org/en/latest/docs/services/apigateway.html

### Additional contract requirements

- `get_api_keys` is a boto3 API Gateway client method. It accepts `nameQuery` (str, optional) and `includeValues` (bool, default `False`). When `nameQuery` is supplied, only API keys whose `name` equals `nameQuery` are returned; when it is omitted or `None`, all API keys are returned. The response is a dict containing an `items` list. When `includeValues` is `True`, each returned key dict contains the secret `value`; when `False`, the `value` field is omitted.
- `get_usage_plan_keys` is a boto3 API Gateway client method. It accepts `usagePlanId` (str, required) and `nameQuery` (str, optional). When `nameQuery` is supplied, only usage-plan keys whose `name` equals `nameQuery` are returned; when it is omitted, all keys for the usage plan are returned. The response is a dict containing an `items` list.
- Additional pagination parameters accepted by the real AWS API (such as `limit`) are accepted by both methods.
