[Question] Assign resource monitor to account level?
Hey,
it's possible to create `snowflake_resource_monitor` resources as well as assigning them to a `snowflake_warehouse`.
What I did not find is assigning a monitor to the account e.g. `ALTER ACCOUNT SET RESOURCE_MONITOR = "resource_monitor_account";`

Did I miss anything or is this currently not supported/implemented?

### Additional contract requirements

- The `snowflake_resource_monitor` resource accepts a boolean attribute `set_for_account` (default `false`). When it is `true`, creating the resource monitor also applies that monitor globally to the Snowflake account.
- Add a public method `SetOnAccount() string` on the resource monitor create builder in package `pkg/snowflake` (the builder returned by `snowflake.ResourceMonitor(name).Create()`). It returns the SQL statement `ALTER ACCOUNT SET RESOURCE_MONITOR = "<name>"`, where `<name>` is the monitor's name.
