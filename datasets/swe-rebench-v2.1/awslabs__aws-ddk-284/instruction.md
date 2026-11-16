Configurator doesnt work as expected when using resource-ids
### Describe the bug

Configurator has 2 ways of working with either resource ids or globally using service like AWS::Lambda::Function. The former is needed to ensure each instance of resource can be given distinctive attributes if needed. Currently if resource id is used, it will be added to all resources in the stack even though its specified for a single id. It leads to errors as some resource might not even support that attribute/parameter

### How to Reproduce

```
"environments": {
    "dev": {
      "account": "222222222222",
      "region": "us-east-1",
      "resources": {
        "AWS::Lambda::Function": {
          "MemorySize": 128,
          "Runtime": "python3.8"
        }
      },
      "tags": {"CostCenter": "2014"}
    },
```

The above works as expected

```

environments: {
      dev: {
        resources: {
          bucket-id-1: {
            BucketName: "my-exact-bucket-name-for-this-resource",
          },
          queue-id-1: {
            KmsMasterKeyId: "alias/aws/sqs",
          },
        },
      },
    },

```

In the above, Configurator will add BucketName parameter to all resource including the queue mentioned. Similarly it will also add the KmsMasterKeyId to all resource of stack including the bucket mentioned above


### Expected behavior

It should only add parameter to the specific resource id

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
