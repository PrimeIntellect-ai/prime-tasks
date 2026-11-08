feature request - ssh public key fingerprints
Perhaps the feature is there but I cannot find it.

Is there a way to obtain the md5 or sha256 fingerprint of a public key?

With ed25519 it can be done as:

` hashlib.md5(key.public_bytes_raw()).hexdigest() `

Other format do not support Raw encoding.

Seems wasteful to have to base64 or DER decode the key bytes, again, to get the raw bytes for hashing.

thank you

### Additional contract requirements

Add a public function `ssh_key_fingerprint(key, hash_algorithm)` importable as
`cryptography.hazmat.primitives.serialization.ssh_key_fingerprint`.

- `key` is an SSH public key of one of the supported SSH public key types
  (for example RSA, Ed25519 or ECDSA).
- `hash_algorithm` is a hash algorithm instance; only `hashes.MD5()` and
  `hashes.SHA256()` are accepted.
- The function returns the raw `bytes` of the hash of the key's SSH binary
  public-key encoding, computed with the given algorithm.
- It raises `TypeError` if `hash_algorithm` is not an MD5 or SHA256 instance.
- It raises `ValueError` if `key` is not a supported SSH public key type.
