Parse does not recognize Pwd as a valid password field alias
**Is your feature request related to a problem? Please describe.**
Yes. When parsing a SQL Server connection string using the [Parse](https://pkg.go.dev/github.com/microsoft/go-mssqldb/msdsn#Parse) function from the msdsn package, the password is not correctly recognized if the field is specified as Pwd instead of [Password](https://github.com/microsoft/go-mssqldb/blob/main/msdsn/conn_str.go#L62). This results in the Password field in the returned [Config](https://pkg.go.dev/github.com/microsoft/go-mssqldb/msdsn#Config) struct being empty, which can cause issues in applications that rely on this value for authentication or further processing.

**Describe the solution you'd like**
It would be helpful if the Parse function could recognize Pwd as a valid alias for Password, similar to how many SQL Server clients treat it. This would improve compatibility with common connection string formats and make the parsing logic more robust and user-friendly.

**Describe alternatives you've considered**
One workaround is to manually replace Pwd with Password in the connection string before parsing, but this is error-prone and bypasses the intended abstraction provided by the Parse function. Another option is to extend the parsing logic downstream, but ideally, the driver should handle common aliases directly.

**Additional context**
Here’s an example of a connection string that fails to populate the password field:
```
Server=localhost;User Id=sa;Pwd=SuperSecret123;
```
In this case, Config.Password remains empty, even though the password was clearly specified. Supporting Pwd as an alias would resolve this inconsistency and align with expectations from other tools and libraries that interface with SQL Server.

Pwd and password are both valid forms: https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlconnection.connectionstring?view=net-9.0-pp#:~:text=equal%20to%2032768.-,Password%0A%2Dor%2D%0APWD,-N/A
