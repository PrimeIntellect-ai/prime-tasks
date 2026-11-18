#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
pip3 install pytest pandas

mkdir -p /app
cat << 'EOF' > /app/audit_compiler.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

int main(int argc, char **argv) {
    if(argc != 3) return 1;
    char *filename = argv[1];
    char *content = argv[2];

    unsigned short fn_len = strlen(filename);
    int content_len = strlen(content);
    int payload_len = 2 + fn_len + content_len;

    unsigned char *payload = malloc(payload_len);
    payload[0] = fn_len & 0xFF;
    payload[1] = (fn_len >> 8) & 0xFF;
    memcpy(payload + 2, filename, fn_len);
    memcpy(payload + 2 + fn_len, content, content_len);

    unsigned char md5[MD5_DIGEST_LENGTH];
    MD5(payload, payload_len, md5);

    fwrite("AUDIT", 1, 5, stdout);
    fwrite(md5, 1, 16, stdout);

    for(int i = 0; i < payload_len; i++) {
        payload[i] ^= 0x5A;
    }
    fwrite(payload, 1, payload_len, stdout);

    free(payload);
    return 0;
}
EOF

gcc /app/audit_compiler.c -o /app/audit_compiler -lcrypto -s
rm /app/audit_compiler.c

useradd -m -s /bin/bash user || true

mkdir -p /home/user/audit_data

python3 -c '
import os
import random
import hashlib

os.makedirs("/home/user/audit_data", exist_ok=True)
truth_lines = ["filename,is_malicious"]

for i in range(500):
    is_mal = random.choice([True, False])
    is_corr = random.choice([True, False]) if random.random() < 0.2 else False

    if is_mal:
        filename = random.choice(["../../../etc/passwd", "/var/log/syslog", "logs/../secret.txt"])
    else:
        filename = f"log_file_{i}.txt"

    content = f"Log content for {i}".encode()
    fn_bytes = filename.encode()
    fn_len = len(fn_bytes)

    payload = fn_len.to_bytes(2, "little") + fn_bytes + content
    md5 = hashlib.md5(payload).digest()
    encoded_payload = bytes([b ^ 0x5A for b in payload])

    magic = b"AUDIT"

    if is_corr:
        corr_type = random.choice([1, 2])
        if corr_type == 1:
            md5 = b"\x00" * 16
        else:
            magic = b"BROKN"

    final_data = magic + md5 + encoded_payload
    file_name = f"log_{i}.bin"
    with open(f"/home/user/audit_data/{file_name}", "wb") as f:
        f.write(final_data)

    label = 1 if (is_mal and not is_corr) else 0
    truth_lines.append(f"{file_name},{label}")

with open("/tmp/ground_truth.csv", "w") as f:
    f.write("\n".join(truth_lines) + "\n")
'

chmod -R 777 /home/user
