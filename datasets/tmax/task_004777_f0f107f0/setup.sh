#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest cryptography

    # Create oracle directory
    mkdir -p /app/oracle
    mkdir -p /app/sandbox-runner-1.2.0

    cat << 'EOF' > /app/oracle/oracle_src.py
import sys
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

def main():
    data = sys.stdin.buffer.read()
    if len(data) < 16:
        return
    nonce = data[:16]
    ciphertext = data[16:]

    key = hashlib.md5(b"EXFIL_FORENSICS_2024").digest()
    cipher = Cipher(algorithms.AES(key), modes.CTR(nonce), backend=default_backend())
    decryptor = cipher.decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    sys.stdout.buffer.write(plaintext)
    sys.stdout.buffer.flush()

if __name__ == "__main__":
    main()
EOF

    echo '#!/bin/bash' > /app/oracle/malware_decoder
    echo '/usr/bin/python3 /app/oracle/oracle_src.py "$@"' >> /app/oracle/malware_decoder
    chmod +x /app/oracle/malware_decoder

    cat << 'EOF' > /app/sandbox-runner-1.2.0/runner.c
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int trigger_unused_warning = 1; // Perturbation
    if (argc < 2) return 1;
    execvp(argv[1], &argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /app/sandbox-runner-1.2.0/Makefile
CC=gcc
CFLAGS=-Wall -Werror

sandbox-runner: runner.c
	$(CC) $(CFLAGS) -o sandbox-runner runner.c

install: sandbox-runner
	cp sandbox-runner /usr/local/bin/
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
