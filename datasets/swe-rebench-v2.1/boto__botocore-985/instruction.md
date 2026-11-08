Region redirect does not honor scheme
Bucket in us-west-2
```
$ aws s3api get-bucket-location --bucket jamesls-test-sync
{
    "LocationConstraint": "us-west-2"
}
```

Specifying an http endpoint to us standard instead of us-west-2:


```
aws s3 cp /tmp/foo.txt s3://jamesls-test-sync/ --endpoint-url http://s3.amazonaws.com/ --debug
```

I can see we have the redirect logic now, but I can see it getting redirected from http to https:

```
2016-07-08 08:57:31,621 - Updating URI from http://s3.amazonaws.com/jamesls-test-sync to https://s3-us-west-2.amazonaws.com/jamesls-test-sync
```

I would expect that if we're going to change the URl we should still honor the scheme they've requested right?

cc @JordonPhillips
