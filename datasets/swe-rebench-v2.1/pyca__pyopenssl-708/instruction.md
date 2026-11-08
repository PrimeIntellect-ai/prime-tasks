Security Implications of #675 (Delete rand.py)
In #675, the rand module was removed from the codebase, and users of the module were instructed to use os.urandom instead. However, using os.urandom is not an alternative for the whole rand module, just for some functions like rand.bytes.

There are other functions in the module, such as rand.add, that are changing the PRNG state of OpenSSL. Using such functions is of particular importance for fork safety, as described here: https://wiki.openssl.org/index.php/Random_fork-safety

and here:
https://docs.python.org/2/library/ssl.html#multi-processing

Please consider reverting #675, or at least bringing back the minimum subset of the rand module that will allow pyopenssl users to deal with fork safety.

### Additional contract requirements

- Add a public function `add(buffer: bytes, entropy: int) -> None` in the module `OpenSSL.rand`. It accepts a byte string `buffer` and an integer `entropy` estimate and returns `None`. It raises `TypeError` if `buffer` is not `bytes` or `entropy` is not `int`.
- Add a public function `status() -> int` in the module `OpenSSL.rand`. It returns an integer; a return value of `1` indicates the PRNG has been seeded with sufficient entropy.
