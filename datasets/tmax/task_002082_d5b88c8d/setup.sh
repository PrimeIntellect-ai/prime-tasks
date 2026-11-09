#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc bubblewrap openssl
pip3 install pytest

mkdir -p /app /eval

# Create a dummy C program for legacy_cert_gen
cat << 'EOF' > /tmp/gen.c
#include <stdio.h>
int main(int argc, char** argv) {
    FILE *f1 = fopen("cert.pem", "w");
    if(f1) { 
        fprintf(f1, "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"); 
        fclose(f1); 
    }
    FILE *f2 = fopen("key.pem", "w");
    if(f2) { 
        fprintf(f2, "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"); 
        fclose(f2); 
    }
    return 0;
}
EOF

gcc -static -s -o /app/legacy_cert_gen /tmp/gen.c
rm /tmp/gen.c

# Create dummy evaluation script
cat << 'EOF' > /eval/test_accuracy.py
#!/usr/bin/env python3
import sys
print("Accuracy: 1.0")
sys.exit(0)
EOF
chmod +x /eval/test_accuracy.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
