Identify capitalisation errors in property names
*cfn-lint version: 0.62.0

* Feature request:
  * It can be hard to identify captalisation errors in cfn property names. It would be useful if cfn-lint would call out these things. An example is:

```
TransformFunction:
    Type: AWS::Lambda::Function
    Properties:
      Code:
        Zipfile: |
```

In this case, Zipfile should be ZipFile... This took me several hours to identify :/

The cfn-lint did pick up the error as:

E3002 Invalid Property Resources/TransformFunction/Properties/Code/Zipfile

Feature request is to call it out more clearly as a capitalisation error and that it might be ZipFile.

This is not the first time this has happened. There are a number of Property names that have unusual capitalisations.

### Additional contract requirements

- For invalid properties at `Resources/myBucketFail/Properties/BucketName1` and `Resources/myBucketPass/Properties/BucketName1`, E3002 must report `Invalid Property Resources/myBucketFail/Properties/BucketName1. Did you mean BucketName?` and `Invalid Property Resources/myBucketPass/Properties/BucketName1. Did you mean BucketName?`, respectively.
