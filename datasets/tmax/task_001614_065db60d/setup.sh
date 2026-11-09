#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create the malicious C code
    cat << 'EOF' > payload.c
#include <stdio.h>
int main() {
    const char* c2 = "C2_IP=198.51.100.99";
    printf("Connecting to %s\n", c2);
    return 0;
}
EOF

    # Compile to ELF
    gcc -O0 payload.c -o payload_orig.bin
    chmod +x payload_orig.bin

    # Hex encode the ELF
    ELF_HEX=$(xxd -p -c 256 payload_orig.bin | tr -d '\n')

    # Create the JSON log
    cat << EOF > traffic_dump.json
[
  {
    "method": "POST",
    "path": "/admin/update",
    "headers": {
      "X-Forwarded-For": "192.168.1.10",
      "User-Agent": "Mozilla/5.0",
      "X-Admin-Token": "62db945239e23616cdcf17b9b18360f0"
    },
    "body": "update=true"
  },
  {
    "method": "POST",
    "path": "/admin/config",
    "headers": {
      "X-Forwarded-For": "203.0.113.88",
      "User-Agent": "curl/7.68.0",
      "X-Admin-Token": "99999999999999999999999999999999"
    },
    "body": "config=1'; DROP TABLE users; -- <script>var p = 'ELF_START:${ELF_HEX}:ELF_END';</script>"
  },
  {
    "method": "GET",
    "path": "/admin/status",
    "headers": {
      "X-Forwarded-For": "10.0.0.5",
      "User-Agent": "CustomApp/1.0",
      "X-Admin-Token": "270ecdb242a35639d67119ffcd90eb6d"
    },
    "body": ""
  }
]
EOF

    rm payload.c payload_orig.bin
    chmod -R 777 /home/user
