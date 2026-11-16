Support TransactionID and Idempotence Consumer/Producers in the Topology
As a user of KTB i would love to setup as well consumers and producers that require transactions and idempotence producing. For this, we need.

* For a producer the DESCRIBE and WRITE operations are given on the topic. The following could be needed as well:
TransactionalId: WRITE, DESCRIBE
Cluster: IDEMPOTENT_WRITE

* For a consumer the READ and DESCRIBE operations are supported on the topic and READ on given consumer group (or default all groups). Not exactly sure at the moment what more we need, but these are possible candidates:
TransactionalId: DESCRIBE
Group: DESCRIBE

### Additional contract requirements

- Producer configuration in a topology descriptor can set the transaction ID with the `transactionId` field and idempotence with the `idempotence` field.
- A producer configured with a transactional ID must receive WRITE and DESCRIBE permissions on that transactional ID.
- A producer configured with a transactional ID or with idempotence enabled must receive the cluster-level IDEMPOTENT_WRITE permission.
