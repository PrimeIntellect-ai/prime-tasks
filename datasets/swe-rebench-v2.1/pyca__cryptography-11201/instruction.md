X509 CommonName fields are not validated for length during certificate creation
Hi PYCA team!

When investigating a difference in behavior with PyOpenSSL behavior, I came across potential issue with X509 certificate creation in cryptography. The current version of the cryptography package can be used to **create** X509 certificates with common name values as empty strings, and with strings that are >64 characters in length. This is a deviation from rfc5280 ( https://datatracker.ietf.org/doc/html/rfc5280#appendix-A.1 ) where ``CommonName`` is defined as ``CommonName ::= PrintableString (SIZE (1..ub-common-name-length))`` and ``ub-common-name-length`` is`` ub-common-name-length INTEGER ::= 64``. The cryptography library allows setting common name values to zero length strings and strings > 64 characters in length.

I am **not** concerned about the ability to **read** a certificate with a CN field that is not conforming with the length specifications, as its clearly possible for in-the-wild certificates to be created with these values. Similar to #10247 there is a good value in being able to read such certificates.

Python version and library components:

```
$ python -V
Python 3.11.4
$ python -m pip list | grep -E "cryptography|pip|cffi|setuptools"
cffi                          1.15.1
cryptography                  42.0.5
pip                           23.2.1
setuptools                    68.0.0
```

Cryptography was installed from pypi using the cryptography-42.0.5-cp39-abi3-manylinux_2_28_x86_64.whl

Example code to make some CA certs with these invalid properties:

```
import os
import sys
import binascii
import datetime

ONE_YEAR_TD = datetime.timedelta(days=365)

import cryptography.x509 as c_x509
import cryptography.hazmat.primitives.hashes as c_hashes
import cryptography.hazmat.primitives.asymmetric.rsa as c_rsa
import cryptography.hazmat.primitives.serialization as c_serialization

def genCert(cname: str, prvkey: c_rsa.RSAPrivateKey) -> c_x509.Certificate:

    pubkey = prvkey.public_key()
    builder = c_x509.CertificateBuilder()
    builder = builder.subject_name(c_x509.Name([
        c_x509.NameAttribute(c_x509.NameOID.COMMON_NAME, cname),
    ]))

    now = datetime.datetime.now(datetime.UTC)
    builder = builder.not_valid_before(now)
    builder = builder.not_valid_after(now + ONE_YEAR_TD)  # certificates are good for 1 years
    builder = builder.serial_number(int(binascii.hexlify(os.urandom(16)).decode('utf8'), 16))
    builder = builder.public_key(pubkey)

    # Mark the cert as a CA - it's just an example
    builder = builder.add_extension(c_x509.BasicConstraints(ca=True, path_length=None), critical=False)

    # Self sign the cert
    builder = builder.issuer_name(c_x509.Name([
        c_x509.NameAttribute(c_x509.NameOID.COMMON_NAME, cname),
    ]))

    certificate = builder.sign(
        private_key=prvkey, algorithm=c_hashes.SHA256(),
    )

    return certificate


def main():

    pkey = c_rsa.generate_private_key(65537, 4096)

    # Per RFC5280 common-name has a length of 1 to 64 characters ?
    # https://datatracker.ietf.org/doc/html/rfc5280#appendix-A.1
    # CommonName ::= PrintableString (SIZE (1..ub-common-name-length))

    # cname with 64 + 1 characters
    cname = 'A' * 65
    print(f'Making a CA cert with common name {cname=} {len(cname)=}')
    cert = genCert(cname=cname, prvkey=pkey)
    print(cert)

    byts = cert.public_bytes(c_serialization.Encoding.PEM)
    with open('long_ca.pem', 'wb') as fd:
        fd.truncate(0)
        fd.write(byts)
    with open('long_ca.key', 'wb') as fd:
        fd.truncate(0)
        fd.write(pkey.private_bytes(encoding=c_serialization.Encoding.PEM,
                                    format=c_serialization.PrivateFormat.TraditionalOpenSSL,
                                    encryption_algorithm=c_serialization.NoEncryption()))

    # Assert the long common name in new cert object can be read and matches cname
    newcert = c_x509.load_pem_x509_certificate(byts)
    newcert_cname = newcert.subject.get_attributes_for_oid(c_x509.NameOID.COMMON_NAME)[0]
    assert newcert_cname.value == cname

    # cname with 0 length string
    cname = ''
    print(f'Making a CA cert with common name {cname=} {len(cname)=}')
    cert = genCert(cname=cname, prvkey=pkey)
    print(cert)

    byts = cert.public_bytes(c_serialization.Encoding.PEM)
    with open('short_ca.pem', 'wb') as fd:
        fd.truncate(0)
        fd.write(byts)
    with open('short_ca.key', 'wb') as fd:
        fd.truncate(0)
        fd.write(pkey.private_bytes(encoding=c_serialization.Encoding.PEM,
                                    format=c_serialization.PrivateFormat.TraditionalOpenSSL,
                                    encryption_algorithm=c_serialization.NoEncryption()))

    # Assert the long common name in new cert object can be read and matches cname
    newcert = c_x509.load_pem_x509_certificate(byts)
    newcert_cname = newcert.subject.get_attributes_for_oid(c_x509.NameOID.COMMON_NAME)[0]
    assert newcert_cname.value == cname

    return 0

if __name__ == '__main__':
    sys.exit(main())
```

Openssl ( from ubuntu 22.04 ) is able to read these certificates:

```
$ openssl version
OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
$ openssl x509 --noout -subject -in short_ca.pem
subject=CN =
$ openssl x509 --noout -subject -in long_ca.pem
subject=CN = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA

```

But openssl cannot create these certificates

```
$ openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 3650
-nodes -subj "/CN=qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnm123456789.com"
<...snip...>
-----
800B18F4C87F0000:error:06800097:asn1 encoding routines:ASN1_mbstring_ncopy:string too long:../crypto/asn1/a_mbstr.c:106:maxsize=64
req: Error adding subject name attribute "/CN=qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnm123456789.com"
```

Likewise, pyopenssl would fail to make such certificates:

```
$ python pyopenssl_long_cname.py
Making a CA cert with common name cname='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' len(cname)=65
/home/epiphyte/PycharmProjects/synapse/pyopenssl_long_cname.py:22: DeprecationWarning: X509Extension support in pyOpenSSL is deprecated. You should use the APIs in cryptography.
  cert.add_extensions([crypto.X509Extension(b'basicConstraints', False, b'CA:TRUE')])
Traceback (most recent call last):
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_long_cname.py", line 64, in <module>
    sys.exit(main())
             ^^^^^^
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_long_cname.py", line 45, in main
    cert = genCert(cname=cname, prvkey=pkey)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_long_cname.py", line 25, in genCert
    cert.get_subject().CN = cname
    ^^^^^^^^^^^^^^^^^^^^^
  File "/home/epiphyte/.pyenv/versions/3.11.4/envs/syn3114/lib/python3.11/site-packages/OpenSSL/crypto.py", line 655, in __setattr__
    _raise_current_error()
  File "/home/epiphyte/.pyenv/versions/3.11.4/envs/syn3114/lib/python3.11/site-packages/OpenSSL/_util.py", line 57, in exception_from_error_queue
    raise exception_type(errors)
OpenSSL.crypto.Error: [('asn1 encoding routines', '', 'string too long')]

$ python pyopenssl_short_cname.py
Making a CA cert with common name cname='' len(cname)=0
/home/epiphyte/PycharmProjects/synapse/pyopenssl_short_cname.py:22: DeprecationWarning: X509Extension support in pyOpenSSL is deprecated. You should use the APIs in cryptography.
  cert.add_extensions([crypto.X509Extension(b'basicConstraints', False, b'CA:TRUE')])
Traceback (most recent call last):
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_short_cname.py", line 63, in <module>
    sys.exit(main())
             ^^^^^^
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_short_cname.py", line 45, in main
    cert = genCert(cname=cname, prvkey=pkey)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/epiphyte/PycharmProjects/synapse/pyopenssl_short_cname.py", line 25, in genCert
    cert.get_subject().CN = cname
    ^^^^^^^^^^^^^^^^^^^^^
  File "/home/epiphyte/.pyenv/versions/3.11.4/envs/syn3114/lib/python3.11/site-packages/OpenSSL/crypto.py", line 655, in __setattr__
    _raise_current_error()
  File "/home/epiphyte/.pyenv/versions/3.11.4/envs/syn3114/lib/python3.11/site-packages/OpenSSL/_util.py", line 57, in exception_from_error_queue
    raise exception_type(errors)
OpenSSL.crypto.Error: [('asn1 encoding routines', '', 'string too short')]
```

The pyopenssl code for reference:

```
$ cat pyopenssl_long_cname.py
import os
import sys
import binascii
import datetime

from OpenSSL import crypto

ONE_YEAR_TD = datetime.timedelta(days=365)

def genCert(cname: str, prvkey: crypto.PKey) -> crypto.X509:

    cert = crypto.X509()
    cert.set_pubkey(prvkey)
    cert.set_version(2)

    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(ONE_YEAR_TD.seconds)  # Certpairs are good for 10 years

    cert.set_serial_number(int(binascii.hexlify(os.urandom(16)).decode('utf8'), 16))

    # Mark the cert as a CA - it's just an example
    cert.add_extensions([crypto.X509Extension(b'basicConstraints', False, b'CA:TRUE')])

    # Set the common name - this raises if cname is invalid length :(
    cert.get_subject().CN = cname

    # Self sign the cert
    cert.set_issuer(cert.get_subject())
    cert.sign(prvkey, 'sha256')
    return cert


def main():

    pkey = crypto.PKey()
    pkey.generate_key(crypto.TYPE_RSA, 4096)

    # Per RFC5280 common-name has a length of 1 to 64 characters ?
    # https://datatracker.ietf.org/doc/html/rfc5280#appendix-A.1
    # CommonName ::= PrintableString (SIZE (1..ub-common-name-length))

    # cname with 64 + 1 characters
    cname = 'A' * 65
    print(f'Making a CA cert with common name {cname=} {len(cname)=}')
    cert = genCert(cname=cname, prvkey=pkey)
    print(cert)

    byts = crypto.dump_certificate(crypto.FILETYPE_PEM, cert)
    with open('pyopenssl_long_ca.pem', 'wb') as fd:
        fd.truncate(0)
        fd.write(byts)
    with open('pyopenssl_long_ca.key', 'wb') as fd:
        fd.truncate(0)
        fd.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, pkey))

    # Assert the long common name in new cert object can be read and matches cname
    newcert = crypto.load_certificate(crypto.FILETYPE_PEM, byts)
    newcert_cname = newcert.get_subject().CN
    assert newcert_cname == cname

    return 0

if __name__ == '__main__':
    sys.exit(main())

$ cat pyopenssl_short_cname.py
import os
import sys
import binascii
import datetime

from OpenSSL import crypto

ONE_YEAR_TD = datetime.timedelta(days=365)

def genCert(cname: str, prvkey: crypto.PKey) -> crypto.X509:

    cert = crypto.X509()
    cert.set_pubkey(prvkey)
    cert.set_version(2)

    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(ONE_YEAR_TD.seconds)  # Certpairs are good for 10 years

    cert.set_serial_number(int(binascii.hexlify(os.urandom(16)).decode('utf8'), 16))

    # Mark the cert as a CA - it's just an example
    cert.add_extensions([crypto.X509Extension(b'basicConstraints', False, b'CA:TRUE')])

    # Set the common name - this raises if cname is invalid length :(
    cert.get_subject().CN = cname

    # Self sign the cert
    cert.set_issuer(cert.get_subject())
    cert.sign(prvkey, 'sha256')
    return cert


def main():

    pkey = crypto.PKey()
    pkey.generate_key(crypto.TYPE_RSA, 4096)

    # Per RFC5280 common-name has a length of 1 to 64 characters ?
    # https://datatracker.ietf.org/doc/html/rfc5280#appendix-A.1
    # CommonName ::= PrintableString (SIZE (1..ub-common-name-length))

    # cname with 0 length string
    cname = ''
    print(f'Making a CA cert with common name {cname=} {len(cname)=}')
    cert = genCert(cname=cname, prvkey=pkey)
    print(cert)

    byts = crypto.dump_certificate(crypto.FILETYPE_PEM, cert)
    with open('pyopenssl_short_ca.pem', 'wb') as fd:
        fd.truncate(0)
        fd.write(byts)
    with open('pyopenssl_short_ca.key', 'wb') as fd:
        fd.truncate(0)
        fd.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, pkey))

    newcert = crypto.load_certificate(crypto.FILETYPE_PEM, byts)
    newcert_cname = newcert.get_subject().CN
    assert newcert_cname == cname

    return 0

if __name__ == '__main__':
    sys.exit(main())
```

I have not dug into any of the rust specific interfaces to see what may differ between the two libraries when calling into openssl library components.
