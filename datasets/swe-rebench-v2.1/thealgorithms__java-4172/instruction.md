[FEATURE REQUEST] Addition of DES to ciphers
### What would you like to Propose?

I feel DES is an important cipher from educational standpoint and thus should be included. Happy to take this up if considered valuable, so please let me know.

### Issue details

Addition of the standard DES Algorithm to Ciphers: https://en.wikipedia.org/wiki/Data_Encryption_Standard

### Additional Information

_No response_

### Additional contract requirements

The DES cipher must be usable through a `DES(String key)` constructor that accepts a 64-character binary key, an `encrypt(String plainText)` operation that returns ciphertext as a binary string, and a `decrypt(String cipherText)` operation that returns the recovered plaintext. The ciphertext uses standard DES block encryption; plaintext shorter than a complete block is padded with null characters to a block boundary, and those padding characters are removed when decrypting.
