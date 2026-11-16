Connection strings formatted like "Data source=address\instance,port..." are not parsed correctly
The code that parses the connection strings seems to correctly parse

`Data source=address,port`

and

`Data source=address\instance`

and

`Data source=address,port\instance`

but not

`Data source=address\instance,port`

which is a valid format when using ADO.NET. But when using mssql to connect using this format the port is always left as the default 1433.
