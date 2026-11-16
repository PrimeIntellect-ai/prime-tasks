[Lex] DescribeResourcePolicy resourceArn malformed
When calling LexModelsV2Response describe_resource_policy the clients resourceArn param becomes encoded somewhere inside core. All colons are replaces with "%3A" which works for the URL string but it also converts the actual resourceArn in the response. This seems to only have an effect on actual AWS ARN shapes which is why the test_lexv2models.py test didn't catch it.

[HIDDEN] but wanted to raise the issue first, in case it has been seen elsewhere before.


Tested in Boto and Moto. Requests seem to be okay/similar.

Moto API Call Below from client.py

OperationModel(name=DescribeResourcePolicy)
**request_dict**
{'url_path': '/policy/arn%3Aaws%3Alex%3Aus-east-1%3A123456789012%3Abot%2F4edca17c-c6f7-4fde-a879-6538653f8a36/', 'query_string': {}, 'method': 'GET', 'headers': {'User-Agent': 'Boto3/1.37.31 md/Botocore#1.37.31 ua/2.1 os/linux#5.15.167.4-microsoft-standard-WSL2 md/arch#x86_64 lang/python#3.12.3 md/pyimpl#CPython cfg/retry-mode#legacy Botocore/1.37.31'}, 'body': b'', 'url': 'https://models-v2-lex.us-east-1.amazonaws.com/policy/arn%3Aaws%3Alex%3Aus-east-1%3A123456789012%3Abot%2F4edca17c-c6f7-4fde-a879-6538653f8a36/', 'context': {'client_region': 'us-east-1', 'client_config': <botocore.config.Config object at 0x7f00cae32bd0>, 'has_streaming_input': False, 'auth_type': None, 'unsigned_payload': None}}

**parsed_response**
{'ResponseMetadata': {'RequestId': 'crWrO9mCaGSwvBEZgX3DkCvKcRyDsOsin4qvm9rnEUkfQfbpeCL7', 'HTTPStatusCode': 200, 'HTTPHeaders': {'server': 'amazon.com', 'date': 'Sat, 12 Apr 2025 19:41:31 GMT', 'x-amzn-requestid': 'crWrO9mCaGSwvBEZgX3DkCvKcRyDsOsin4qvm9rnEUkfQfbpeCL7'}, 'RetryAttempts': 0}, **'resourceArn': 'arn%3Aaws%3Alex%3Aus-east-1%3A123456789012%3Abot%2F4edca17c-c6f7-4fde-a879-6538653f8a36',** 'policy': '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::123456789012:root"}, "Action": "lex:*", "Resource": "arn:aws:lex:us-east-1:123456789012:bot/4edca17c-c6f7-4fde-a879-6538653f8a36"}]}', 'revisionId': '87be0f4f-0fa4-400a-8ca7-f7c09006861e'}


[lexv2_RP_testing.txt](https://github.com/user-attachments/files/19726088/lexv2_RP_testing.txt)

### Additional contract requirements

- The same percent-encoding defect affects every LexModelsV2 resource-policy operation, not only `describe_resource_policy`. The `resourceArn` returned by `create_resource_policy`, `describe_resource_policy`, `update_resource_policy`, and `delete_resource_policy` must be the decoded ARN exactly as supplied by the caller (for example, `arn:aws:lex:eu-west-1:123456789012:bot/MyLexBot`), with no percent-encoding such as `%3A` or `%2F`.
