[RDS - Moto 5.1.3] stop_db_instance does not respect DBSnapshotIdentifier as manual snapshots
When calling stop_db_instance, you can provide a DBSnapshotIdentifier to create a manual snapshot as part of the db stop action. However, moto incorrectly tags this snapshot as an "automatic" snapshot instead of a manual one.

Example Code:
```python

#stop db instance (should create a manual snapshot)
rds_client.stop_db_instance(DBInstanceIdentifier="myInstance", DBSnapshotIdentifier="mySnapshot")


# returns empty (should return a snapshot)
rds_client.describe_db_snapshots(
            DBInstanceIdentifier=rds_instance, SnapshotType="manual"
        )
```

running the describe_db_snapshots command without the SnapshotType filter does return the snapshot, but it is incorrectly tagged as "automatic"

prio to moto 5.1, my automated tests worked fine because they (unknowingly) leveraged the bug that was fixed in the commit mentioned in #8658. however, now there is both an automated snapshot along with my manual snapshot that I am trying to test for, so my tests that were previously looking for the presense/absense of a snapshot no longer work, and this bug with not correctly tagging the snapshot as a manual snapshot prevents me from being able to update the tests to correctly query for manual snapshots.
