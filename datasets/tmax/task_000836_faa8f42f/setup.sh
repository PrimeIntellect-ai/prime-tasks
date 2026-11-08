#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl gcc libc6-dev yara
pip3 install pytest

# Create directories
mkdir -p /home/user/forensics/certs
mkdir -p /home/user/forensics/system_files
mkdir -p /home/user/workspace
mkdir -p /home/user/evidence

# 1. Create upload_handler.c (Vulnerability: CWE-121 or CWE-120)
cat << 'EOF' > /home/user/forensics/upload_handler.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void handle_upload() {
    char buffer[256];
    char *content_length = getenv("HTTP_CONTENT_LENGTH");
    if (content_length) {
        // Classic stack-based buffer overflow
        strcpy(buffer, content_length);
    }
}
int main() { handle_upload(); return 0; }
EOF

# 2. Create Certificates
cd /home/user/forensics/certs
# Generate root CA
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout ca_key.pem -out ca_chain.pem -subj "/C=US/O=Forensics/CN=RootCA" 2>/dev/null
# Generate valid cert
openssl req -newkey rsa:2048 -nodes -keyout imp1_key.pem -out imp1.csr -subj "/C=US/O=Evil/CN=c2-alpha.malicious.local" 2>/dev/null
openssl x509 -req -in imp1.csr -CA ca_chain.pem -CAkey ca_key.pem -CAcreateserial -out implant_1.pem -days 365 2>/dev/null
# Generate invalid cert (self-signed)
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout imp2_key.pem -out implant_2.pem -subj "/C=US/O=Evil/CN=c2-beta.malicious.local" 2>/dev/null
# Generate another invalid cert (wrong CA)
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout fake_ca.pem -out fake_ca.crt -subj "/CN=FakeCA" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout imp3_key.pem -out imp3.csr -subj "/C=US/O=Evil/CN=c2-gamma.malicious.local" 2>/dev/null
openssl x509 -req -in imp3.csr -CA fake_ca.crt -CAkey fake_ca.pem -CAcreateserial -out implant_3.pem -days 365 2>/dev/null
rm -f *.csr *.srl ca_key.pem imp1_key.pem imp2_key.pem imp3_key.pem fake_ca.*

# 3. Create payload.enc
cd /home/user/forensics
# Make a dummy binary implant containing the signature "SIG_DEADC0DE"
echo -n -e "\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" > dummy.bin
echo -n "Random data before signature... SIG_DEADC0DE ... random data after" >> dummy.bin
# XOR with 0x42 and base64 encode
python3 -c '
import base64
with open("dummy.bin", "rb") as f:
    data = f.read()
xored = bytes([b ^ 0x42 for b in data])
with open("payload.enc", "wb") as f:
    f.write(base64.b64encode(xored))
'
rm -f dummy.bin

# 4. Create system files for pattern matching
cd /home/user/forensics/system_files
echo "clean file 1" > syslogd
echo "clean file 2" > kernel_task
echo "infected file 1: SIG_DEADC0DE hidden here" > crond_helper
echo "clean file 3" > bash_profile
echo "infected file 2: SIG_DEADC0DE is present" > sshd_monitor

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
