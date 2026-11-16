VerifyingKey Q=(n-1)*G fails with "AttributeError"
Using a public key that corresponds to d=n-1, i.e.

```import ecdsa
sk = ecdsa.SigningKey.from_string((ecdsa.NIST256p.order - 1).to_bytes(32, 'big'),
    curve = ecdsa.NIST256p)
vk = sk.verifying_key
sg = sk.sign(b"hello")
vk.verify(sg, b"hello")
```

results in:

```$ python3 foo.py
Traceback (most recent call last):
  File "foo.py", line 5, in <module>
    vk.verify(sg, b"hello")
  File "/usr/local/lib/python3.6/dist-packages/ecdsa/keys.py", line 602, in verify
    return self.verify_digest(signature, digest, sigdecode, True)
  File "/usr/local/lib/python3.6/dist-packages/ecdsa/keys.py", line 652, in verify_digest
    if self.pubkey.verifies(number, sig):
  File "/usr/local/lib/python3.6/dist-packages/ecdsa/ecdsa.py", line 167, in verifies
    xy = G.mul_add(u1, self.point, u2)
  File "/usr/local/lib/python3.6/dist-packages/ecdsa/ellipticcurve.py", line 609, in mul_add
    both = (self + other).scale()
AttributeError: 'Point' object has no attribute 'scale'
```
