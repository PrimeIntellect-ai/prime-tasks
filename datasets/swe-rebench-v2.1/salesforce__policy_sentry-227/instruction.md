Missing condition keys for s3
Was doing some investigative work on condition keys for s3:

The following returns nothing:

```policy_sentry query condition-table --service s3```

but according to [the docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/list_amazons3.html), it should return many.

This is version 0.8.7 and after having done a ```policy_sentry initialize --fetch --build```
