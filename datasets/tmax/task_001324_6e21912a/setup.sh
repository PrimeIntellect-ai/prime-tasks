#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest cryptography

    mkdir -p /app /test/corpus/evil /test/corpus/clean

    cat << 'EOF' > /app/c2_auth_check.c
#include <stdio.h>
#include <string.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/sha.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    X509 *cert = PEM_read_X509(f, NULL, NULL, NULL);
    fclose(f);
    if (!cert) return 1;

    if (X509_NAME_cmp(X509_get_issuer_name(cert), X509_get_subject_name(cert)) != 0) {
        return 1;
    }

    X509_NAME *subj = X509_get_subject_name(cert);
    int loc = X509_NAME_get_index_by_NID(subj, NID_commonName, -1);
    if (loc == -1) return 1;
    X509_NAME_ENTRY *entry = X509_NAME_get_entry(subj, loc);
    ASN1_STRING *data = X509_NAME_ENTRY_get_data(entry);
    const char *cn = (const char *)ASN1_STRING_get0_data(data);
    int len = ASN1_STRING_length(data);
    const char *suffix = ".c2.internal";
    int suffix_len = strlen(suffix);
    if (len < suffix_len || strcmp(cn + len - suffix_len, suffix) != 0) {
        return 1;
    }

    unsigned char *der = NULL;
    int der_len = i2d_X509(cert, &der);
    if (der_len < 0) return 1;
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(der, der_len, hash);
    OPENSSL_free(der);

    if (hash[0] != 0) return 1;

    return 0;
}
EOF

    gcc /app/c2_auth_check.c -o /app/c2_auth_check -lssl -lcrypto
    strip /app/c2_auth_check
    rm /app/c2_auth_check.c

    cat << 'EOF' > /tmp/gen_certs.py
import os
import hashlib
import datetime
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

def generate_cert(is_evil, filename):
    while True:
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

        cn = "test.c2.internal" if is_evil else "test.com"
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, cn),
        ])

        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.datetime.utcnow()
        ).not_valid_after(
            datetime.datetime.utcnow() + datetime.timedelta(days=10)
        ).sign(private_key, hashes.SHA256())

        der = cert.public_bytes(serialization.Encoding.DER)
        digest = hashlib.sha256(der).hexdigest()

        if is_evil:
            if digest.startswith("00"):
                break
        else:
            break

    with open(filename, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))

for i in range(5):
    generate_cert(True, f"/test/corpus/evil/cert_{i}.pem")
for i in range(5):
    generate_cert(False, f"/test/corpus/clean/cert_{i}.pem")
EOF

    python3 /tmp/gen_certs.py
    rm /tmp/gen_certs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
