RDS create_db_instance throws KeyError if cluster doesn't exist on 5.1.0
We have some code that just creates a database instance. It started throwing a `KeyError` on the 5.1.0 release when calling create_db_instance:

Our code:

```
        client = boto3.client("rds", region_name="us-west-2")

        client.create_db_instance(
            DBClusterIdentifier="cluster_id",
            DBInstanceClass="r6i.large",
            DBInstanceIdentifier="cluster_id-0",
            Engine="aurora-postgresql",
            Tags=[],
        )
```

Stack trace:

```
  File "test.py", line 15, in setUp
    client.create_db_instance(
<redacted retry middleware noise>
  File "/lib/python3.11/site-packages/moto/rds/responses.py", line 80, in create_db_instance
    database = self.backend.create_db_instance(db_kwargs)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/lib/python3.11/site-packages/moto/rds/models.py", line 2181, in create_db_instance
    database = DBInstanceClustered(backend=self, **db_kwargs)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/lib/python3.11/site-packages/moto/rds/models.py", line 1503, in __init__
[HIDDEN]
                   ~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
KeyError: 'cluster_id'
```

Our code was obviously wrong, but earlier versions of moto actually worked with it for some reason. I would think this should throw a more useful exception, though, like whatever boto will throw when it encounters this situation of someone creating an instance on a nonexistent cluster.
