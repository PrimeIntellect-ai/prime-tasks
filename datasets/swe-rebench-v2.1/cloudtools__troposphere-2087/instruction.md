RDS Validiation: minimum allocated storage for Provisioned IOPS for SQLServer is 20GiB, not 100GiB
Troposphere validates the minimum allocated storage required for provisioned iops at 100
https://github.com/cloudtools/troposphere/blob/main/troposphere/validators/rds.py#L345

For SQLServer, the minimum is 20
https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html#USER_PIOPS

### Additional contract requirements

- When allocated storage is below this minimum for SQL Server with provisioned IOPS, raise a ValueError whose message contains the exact text ` must be at least 20 `.
