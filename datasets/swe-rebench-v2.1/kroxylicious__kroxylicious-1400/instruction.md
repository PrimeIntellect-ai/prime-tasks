Expose record encryption parameters to configuration
              piggybacking a small feature request onto this issue - `RecordEncryption` currently [hardcodes 5 million encryptions per DEK](https://github.com/kroxylicious/kroxylicious/blob/11c1a14ebecf04604df34f5c535783145247ad82/kroxylicious-filters/kroxylicious-record-encryption/src/main/java/io/kroxylicious/filter/encryption/RecordEncryption.java#L106) and it would be nice if that value were configurable - or, failing that, if it were set low enough not to encrypt more data than would weaken the GCM key given a suitably pessimistic average message size.

After reading that last half sentence, I think it'd be better for it to be configurable. I don't personally have a use-case for having different DEK rotation requirements for different levels of sensitive data, so a single value is enough for me.

_Originally posted by @ddaviesbrackett-dwp in https://github.com/kroxylicious/kroxylicious/issues/1042#issuecomment-2141697948_

### Additional contract requirements

Record encryption accepts a single maximum-encryptions-per-DEK limit through the experimental configuration entry `maxEncryptionsPerDek`. The configured limit governs how many encryption operations may be performed with a DEK before a replacement DEK is needed. When this entry is absent or null, preserve the existing default of five million encryptions per DEK.
