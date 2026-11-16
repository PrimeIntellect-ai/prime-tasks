Connector should error on invalid IAM AuthN calls
If a database engine doesn't support Auto IAM AuthN (i.e., MySQL, SQL Server), the connector should throw an error if a user has requested the feature.

Related: https://github.com/GoogleCloudPlatform/cloud-sql-go-connector/issues/283.
