[Bug] ServiceKey is overwritten on every restart when MasterKeyPassword is used
**Describe the bug**
We generate a [ServiceKey](https://github.com/TBD54566975/ssi-service/blob/main/pkg/service/keystore/storage.go#L108) on every call to [NewEncryption](https://github.com/TBD54566975/ssi-service/blob/main/pkg/service/keystore/storage.go#L99). The result is that encryption is broken across deployments/pods.

**To Reproduce**
1. Run ssi-service with more than one replica.
2. Create a key with replica 1.
3. Read the key with replica 2.
4. Note that the previous step fails with an error.

**Expected behavior**
There should be no error.

### Additional contract requirements

- The public function `NewKeyStoreService(config config.KeyStoreServiceConfig, s storage.ServiceStorage) (*Service, error)` in package `pkg/service/keystore` must ensure the service encryption key exists before returning a usable keystore service: if the key is already present it must be left unchanged, and if it is absent it must be created using the configured master password and stored.
- Creating the keystore service must return a non-nil error if the service encryption key cannot be created or stored.
