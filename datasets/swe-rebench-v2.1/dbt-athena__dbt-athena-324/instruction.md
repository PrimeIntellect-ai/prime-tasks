Error running dbt docs generate with Federated Query database
I'm trying to run `dbt docs generate` with Federated Query data using the Redshift Connector and it returns the following error:

```
[0m15:45:16.272788 [debug] [ThreadPool]: Acquiring new athena connection 'awsdatacatalog.information_schema'
[0m15:45:16.273878 [debug] [ThreadPool]: Acquiring new athena connection 'redshiftCatalog_dev.information_schema'
[0m15:45:16.274842 [debug] [ThreadPool]: Opening a new connection, currently in state init
[0m15:45:16.275793 [debug] [ThreadPool]: Opening a new connection, currently in state init
[0m15:45:17.416799 [debug] [ThreadPool]: On redshiftCatalog_dev.information_schema: Close
[0m15:45:17.419386 [warn ] [MainThread]: Encountered an error while generating catalog: 'catalog-id'
[0m15:45:20.555092 [debug] [ThreadPool]: On awsdatacatalog.information_schema: Close
[0m15:45:20.707223 [error] [MainThread]: dbt encountered 1 failure while writing the catalog
[0m15:45:20.709353 [info ] [MainThread]: Catalog written to /app/target/catalog.json
```

I'm aware of #247 but believe this is an issue with using non-glue data catalogs.

The catalog file and html are generated and aparently look fine, but the error is returned nonetheless.
