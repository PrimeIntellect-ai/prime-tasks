Crypto 3.0: Switch to byte array for counter in vault unlock
The `decryptVaultEncryptionKey() `and `encryptVaultEncryptionKey()` methods are marked as deprecated, however there is no available replacement for original version 2.0 logic which uses the counter. We should introduce a `byte[]` argument for the counter and switch to it, as it was done for other methods with numeric counter (for consistency reasons it is better to use `byte[]` than keeping original `long` type, although this method is only used for version 2.0 logic). The Crypto 3.0 vault encryption and decryption methods do not need a counter, so they are not affected.

Deprecated methods:
https://github.com/wultra/powerauth-crypto/blob/features/crypto3/powerauth-java-crypto/src/main/java/io/getlime/security/powerauth/crypto/client/vault/PowerAuthClientVault.java#L55
https://github.com/wultra/powerauth-crypto/blob/features/crypto3/powerauth-java-crypto/src/main/java/io/getlime/security/powerauth/crypto/server/vault/PowerAuthServerVault.java#L56
