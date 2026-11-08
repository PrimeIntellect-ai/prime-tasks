Refactor "connect" into "connect_info"
Update "ICM.connect" to "ICM.connect_info"

This should also move the "connect_with_XXXX" functions up to the connector level as well.

### Additional contract requirements

- `InstanceConnectionManager.connect_info(ip_type)` returns a tuple `(InstanceMetadata, str)`: the refreshed instance metadata followed by the IP address selected for the requested `ip_type`.
- The driver-specific connection helpers (formerly `InstanceConnectionManager._connect_with_XXXX`) are exposed as module-level `connect` functions in the `google.cloud.sql.connector.pymysql`, `google.cloud.sql.connector.pg8000`, and `google.cloud.sql.connector.pytds` modules, each accepting `(ip_address, ctx, **kwargs)`.
- `connector.connect` raises `KeyError` when the requested driver is not one of the supported drivers (`pymysql`, `pg8000`, `pytds`).
