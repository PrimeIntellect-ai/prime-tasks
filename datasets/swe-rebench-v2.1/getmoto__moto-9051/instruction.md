Implement EC2 DescribeImages filter 'source-instance-id'

Documentation: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeImages.html

If I define the filter 'source-instance-id', it returns the error: The filter 'source-instance-id' for DescribeImages has not been implemented in Moto yet. Feel free to open an issue at https://github.com/getmoto/moto/issues

### Additional contract requirements

- When `DescribeImages` returns an image created from an instance, include `SourceInstanceId` with that instance's ID.
