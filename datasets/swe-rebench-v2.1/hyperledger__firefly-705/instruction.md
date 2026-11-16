Aggregator stuck on environment in latest mainline
Aggregator stuck on this:
```
[2022-04-12T19:52:09.498Z] ERROR node_0: SQL insert failed: UNIQUE constraint failed: contractapis.namespace, contractapis.name sql=[ INSERT INTO contractapis (id,interface_id,location,name,namespace,message_id) VALUES ($1,$2,$3,$4,$5,$6) ]: UNIQUE constraint failed: contractapis.namespace, contractapis.name dbtx=HMQh6mZQ role=aggregator
[2022-04-12T19:52:09.498Z]  INFO node_0: Result of definition broadcast 'ff_define_contract_api' [ce2f2857-963d-49b1-a774-fe30c2dc67d7]: retry dbtx=HMQh6mZQ role=aggregator
[2022-04-12T19:52:09.499Z]  WARN node_0: SQL! transaction rollback dbtx=HMQh6mZQ role=aggregator
[2022-04-12T19:52:09.499Z] ERROR node_0: process events attempt 25: FF10116: Database insert failed: UNIQUE constraint failed: contractapis.namespace, contractapis.name role=ep[ff_system:ff_aggregator]
```
[output.log](https://github.com/hyperledger/firefly/files/8476365/output.log)

### Additional contract requirements

- `SQLCommon.UpsertContractAPI(ctx context.Context, api *fftypes.ContractAPI) error` in package `internal/database/sqlcommon` inserts a new contract API or updates an existing one identified by its namespace and name. When a record already exists for that namespace and name and the supplied `api.ID` is non-nil and differs from the stored record's ID, the call returns the `database.IDMismatch` error instead of updating the record.
- `Plugin.UpsertContractAPI(ctx context.Context, api *fftypes.ContractAPI) error` in package `github.com/hyperledger/firefly/pkg/database` has the same upsert-by-namespace-and-name semantics and returns `database.IDMismatch` when the supplied ID conflicts with the existing record's ID.
- `database.IDMismatch` is the sentinel error value in package `github.com/hyperledger/firefly/pkg/database` that signals such an ID conflict.
- When a contract API definition is processed and its ID conflicts with the existing record for the same namespace and name, the definition is rejected as invalid and is not retried (no error is propagated for retry).
