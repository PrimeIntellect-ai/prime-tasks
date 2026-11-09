#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils
pip3 install pytest cryptography pycryptodome

mkdir -p /app
cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/aes.h>

void pkcs7_pad(unsigned char *data, int *len) {
    int pad = 16 - (*len % 16);
    for (int i = 0; i < pad; i++) {
        data[*len + i] = pad;
    }
    *len += pad;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <username> <password>\n", argv[0]);
        return 1;
    }

    char *key_str = "d3vS3c0ps_k3y123";
    AES_KEY enc_key;
    AES_set_encrypt_key((unsigned char *)key_str, 128, &enc_key);

    unsigned char buffer[256];
    memset(buffer, 0, sizeof(buffer));
    int len = snprintf((char *)buffer, sizeof(buffer), "%s:%s", argv[1], argv[2]);

    pkcs7_pad(buffer, &len);

    unsigned char out[256];
    for (int i = 0; i < len; i += 16) {
        AES_ecb_encrypt(buffer + i, out + i, &enc_key, AES_ENCRYPT);
    }

    printf("TOKEN: ");
    for (int i = 0; i < len; i++) {
        printf("%02x", out[i]);
    }
    printf("\n");

    return 0;
}
EOF

gcc -O2 /app/legacy_auth.c -o /app/legacy_auth -lssl -lcrypto
strip /app/legacy_auth
rm /app/legacy_auth.c

cat << 'EOF' > /app/verifier.py
import subprocess
import random
import string
import sys

def rand_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

matches = 0
total = 50

for _ in range(total):
    user = rand_string(random.randint(4, 12))
    pwd = rand_string(random.randint(8, 20))

    try:
        expected = subprocess.check_output(['/app/legacy_auth', user, pwd], text=True).strip()
        actual = subprocess.check_output(['python3', '/home/user/secure_auth.py', user, pwd], text=True).strip()
        if expected == actual:
            matches += 1
    except Exception:
        pass

accuracy = matches / total
print(f"Accuracy: {accuracy}")
if accuracy >= 1.0:
    sys.exit(0)
else:
    sys.exit(1)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
