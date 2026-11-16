Directory Service: DescribeDirectories expects LaunchTime to be a JSON Number, got string instead
Hello,
I'm using moto server with Terraform, creating a AWS Directory Service instance. I think there was a change in the API for `ds:DescribeDirectories`, or maybe just new validation on the response. But using the latest moto version, 5.0.12, I'm seeing the following error:

```
Error: reading Directory Service Directory (d-7b4fdb73d6): operation error Directory Service: DescribeDirectories, https response error StatusCode: 200, RequestID: QjGxElo4976zUbXqHjhAzLjSYn2WHHZ0VA46AmJTfyjldHWH6hVP, deserialization failed, failed to decode response body, expected LaunchTime to be a JSON Number, got string instead

  with module.directory_service.aws_directory_service_directory.this,
  on ../../main.tf line 1, in resource "aws_directory_service_directory" "this":
   1: resource "aws_directory_service_directory" "this" {
```

Checking the code, I see it is writing a datetime string in isoformat:

https://github.com/getmoto/moto/blob/2a8bb4a6fc06ad91ad1b234ccb11c1199b0898f2/moto/ds/models.py#L83

Looking up the API doc for the command, the response syntax for LaunchTime is actually a number.

https://docs.aws.amazon.com/directoryservice/latest/devguide/API_DescribeDirectories.html#API_DescribeDirectories_Examples
