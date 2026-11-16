HealthCheck fails with 400 bad request
### Which service(blob, file, queue, table) does this issue concern?
Table

### Which version of the Azurite was used?
3.31.0

### Where do you get Azurite? (npm, DockerHub, NuGet, Visual Studio Code Extension)
DockerHub

### What's the Node.js version?
NA

### What problem was encountered?

```
The query condition specified in the request is invalid.\nRequestId:47a6a1bb-5a89-47e9-8dda-954ba86566dd\nTime:2024-08-09T14:03:38.156Z\r\nStatus: 400 (Bad Request)\r\nErrorCode: InvalidInput\r\n\r\nContent:\r\n{\"odata.error\":{\"code\":\"InvalidInput\",\"message\":{\"lang\":\"en-US\",\"value\":\"The query condition specified in the request is invalid.\\nRequestId:47a6a1bb-5a89-47e9-8dda-954ba86566dd\\nTime:2024-08-09T14:03:38.156Z\"}}}\r\n\r\nHeaders:\r\nServer: Azurite-Table/3.31.0\r\nx-ms-error-code: REDACTED\r\nx-ms-request-id: 47a6a1bb-5a89-47e9-8dda-954ba86566dd\r\nx-ms-version: REDACTED\r\nDate: Fri, 09 Aug 2024 14:03:38 GMT\r\nConnection: keep-alive\r\nKeep-Alive: REDACTED\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json;odata=minimalmetadata;streaming=true;charset=utf-8\r\n
```

Health check source code:

https://github.com/Xabaril/AspNetCore.Diagnostics.HealthChecks/blob/master/src/HealthChecks.Azure.Data.Tables/AzureTableServiceHealthCheck.cs

### Steps to reproduce the issue?

After switching to Azurite, using the default health checker that comes with the Aspire component for adding azure table storage, the health check is receiving a 400 bad request.

1. Create a new Aspire app
2. Add azurite to apphost
  ```C#
  // Add Azure Storage
  var storage = builder.AddAzureStorage("storage")
      .RunAsEmulator(c => c.WithImageTag("3.31.0").WithDataVolume();
  );
  var yourComponent = storage.AddTables("yourcomponent");
  ```
3. Add a client app which loads the component, then enable health checks
  ```C#
  builder.AddKeyedAzureTableClient("yourcomponent");
  ```

### Have you found a mitigation/solution?

Not yet

### Additional contract requirements

The Table health check probes the service by issuing a query whose OData filter value is `false` (see the linked `AzureTableServiceHealthCheck` source). Azurite must therefore accept the following simple filter values for both entity queries (listing entities through a table client) and table listing (listing tables through a table service client):

- An empty filter (`""`) or the filter `true` matches every item.
- The filter `false` matches no items.

Any other filter value is parsed as a normal OData query expression.
